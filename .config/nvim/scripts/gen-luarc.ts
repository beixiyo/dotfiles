#!/usr/bin/env bun

import { readdirSync, readFileSync, statSync, writeFileSync } from 'fs'
import { join, resolve } from 'path'

const CONFIG = resolve(import.meta.dir, '..')
const HOME = process.env.HOME ?? resolve(CONFIG, '..', '..')
const DATA = process.env.XDG_DATA_HOME
  ? join(process.env.XDG_DATA_HOME, 'nvim')
  : join(HOME, '.local', 'share', 'nvim')

const PACK_ROOT = join(DATA, 'site', 'pack')
const VENDOR_ROOT = join(CONFIG, 'vendors')
const MANIFEST_PATH = join(CONFIG, '.luarc-libraries.json')

// WSL + Windows bun: resolve 产出 UNC 路径，lua_ls 需要 POSIX
const WSL_UNC_RE = /^\\\\wsl\.localhost\\[^\\]+/
const FS_ROOT = CONFIG.match(WSL_UNC_RE)?.[0] ?? '/'

function toPosix(p: string) {
  if (!WSL_UNC_RE.test(p)) return p.replaceAll('\\', '/')
  return p.replace(WSL_UNC_RE, '').replaceAll('\\', '/')
}

function isDir(p: string) {
  try {
    return statSync(p).isDirectory()
  }
  catch {
    return false
  }
}

function scanPluginParent(dir: string) {
  if (!isDir(dir)) return [] as string[]
  return readdirSync(dir)
    .filter((name: string) => isDir(join(dir, name, 'lua')))
    .map((name: string) => join(dir, name))
}

function walkLuaFiles(dir: string): string[] {
  if (!isDir(dir)) return []

  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const path = join(dir, entry.name)
    if (entry.isDirectory()) return walkLuaFiles(path)
    return entry.isFile() && entry.name.endsWith('.lua') ? [path] : []
  })
}

function moduleNames(plugin: string) {
  const luaDir = join(plugin, 'lua')
  if (!isDir(luaDir)) return []

  return readdirSync(luaDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() || entry.name.endsWith('.lua'))
    .map((entry) =>
      entry.isDirectory()
        ? entry.name
        : entry.name.slice(0, -'.lua'.length)
    )
}

function requiredModules(plugin: string) {
  const modules = new Set<string>()
  const requirePattern = /\brequire\s*(?:\(\s*)?(['"])([^'"]+)\1/g

  for (const file of walkLuaFiles(join(plugin, 'lua'))) {
    const source = readFileSync(file, 'utf8')
    for (const match of source.matchAll(requirePattern)) {
      modules.add(match[2].split('.')[0])
    }
  }

  return modules
}

function scanPackRoot() {
  if (!isDir(PACK_ROOT)) return [] as string[]
  return readdirSync(PACK_ROOT).flatMap((group: string) => ['opt', 'start'].flatMap((type) => scanPluginParent(join(PACK_ROOT, group, type))))
}

function findNvimRuntime() {
  const candidates = [
    join(FS_ROOT, 'usr', 'share', 'nvim', 'runtime', 'lua'),
    join(FS_ROOT, 'usr', 'local', 'share', 'nvim', 'runtime', 'lua'),
    join(FS_ROOT, 'opt', 'homebrew', 'share', 'nvim', 'runtime', 'lua'),
  ]
  return candidates.filter(isDir)
}

const libraries = [
  ...findNvimRuntime(),
  ...scanPackRoot(),
  ...scanPluginParent(VENDOR_ROOT),
].map((path) => resolve(path)).sort()

const providers = new Map<string, string>()
for (const library of libraries) {
  for (const moduleName of moduleNames(library)) {
    if (!providers.has(moduleName)) providers.set(moduleName, library)
  }
}

const projects = Object.fromEntries(
  scanPluginParent(VENDOR_ROOT).map((project) => {
    const dependencies = [...requiredModules(project)]
      .map((moduleName) => providers.get(moduleName))
      .filter((dependency): dependency is string => dependency !== undefined && dependency !== project)
      .map(toPosix)
      .sort()

    return [toPosix(resolve(project)), [...new Set(dependencies)]]
  }),
)

const base = [
  '${3rd}/luv/library',
  ...findNvimRuntime().map((path) => toPosix(resolve(path))),
]

// ---------------------------------------------------------------------------
// 根项目文件级 library
//
// spec 只通过字符串引用插件（如 main = 'vv-splits'），不会 require 其类型；
// 若把整个插件目录加入 library，LuaLS 会索引上千文件。这里只收集 spec 注解中
// 实际用到的类型名，定位声明它的文件，再沿这些文件自身的注解做传递闭包
// ---------------------------------------------------------------------------

// `---@class (exact) Name<T> : Parent` 中 name 允许 `.` `-`，修饰符和泛型参数需跳过；
// LuaLS 也接受 `--- @class`（gitsigns / blink.cmp 等用这种写法）
// 修饰符可紧贴关键字：`---@alias(partial) X` / `---@enum(key, partial) X`
const DECL_RE = /^\s*---\s*@(class|alias|enum)(?:\s*\([^)]*\))?\s+([A-Za-z_][\w.\-]*)/
const TAG_RE = /^\s*---\s*@(type|return|param|as|cast|generic|field|class|alias|enum)(?=[\s(])\s*(.*)$/
const INLINE_AS_RE = /--\[=*\[\s*@as\s+(.*?)\]=*\]/g
const ALIAS_ITEM_RE = /^\s*---\|\s*(.*)$/
// 后跟 `:` / `?:` 的是 `fun(a: T)` / `{ a: T }` 里的参数名或字段名，不是类型
const IDENT_RE = /([A-Za-z_][\w.\-]*)(\s*\??\s*:)?/g
const FIELD_SCOPES = new Set(['public', 'private', 'protected', 'package'])

// 仅用于未解析列表降噪：LuaLS 内置类型本来就不需要 library
const LUALS_BUILTINS = new Set([
  'nil',
  'any',
  'boolean',
  'string',
  'number',
  'integer',
  'function',
  'table',
  'thread',
  'userdata',
  'lightuserdata',
  'fun',
  'unknown',
  'self',
  'true',
  'false',
])

/** 取开头一个类型表达式：遇到不在括号 / 尖括号内的空白即结束 */
function leadingTypeExpr(text: string) {
  let depth = 0

  for (let i = 0; i < text.length; i++) {
    const ch = text[i]
    if ('(<[{'.includes(ch)) depth++
    else if (')>]}'.includes(ch)) depth--
    else if (/\s/.test(ch) && depth <= 0) {
      // `fun(): T` 的返回类型跟在冒号空格后，属于同一个表达式
      if (text[i - 1] === ':') continue

      // `A | B` 两侧带空格的联合类型也属于同一个表达式
      const prev = text.slice(0, i).trimEnd().at(-1)
      const next = text.slice(i).trimStart()[0]
      if (prev === '|' || next === '|') continue

      return text.slice(0, i)
    }
  }

  return text
}

/** 按不在括号 / 尖括号内的逗号切分，`table<K, V>`、`{ a: T, b: U }` 保持完整 */
function splitTopLevel(text: string) {
  const parts: string[] = []
  let depth = 0
  let start = 0

  for (let i = 0; i < text.length; i++) {
    const ch = text[i]
    if ('(<[{'.includes(ch)) depth++
    else if (')>]}'.includes(ch)) depth--
    else if (ch === ',' && depth <= 0) {
      parts.push(text.slice(start, i).trim())
      start = i + 1
    }
  }

  parts.push(text.slice(start).trim())
  return parts
}

/** 跳过开头一个 token（参数名、字段名、cast 变量名） */
function skipName(text: string) {
  return text.replace(/^\S+\s*/, '')
}

/** 提取一行注解里引用的类型名；描述文本不参与，避免把注释词当类型 */
function referencedTypeNames(line: string) {
  const alias = line.match(ALIAS_ITEM_RE)
  const tag = line.match(TAG_RE)

  let exprs: string[] = []

  if (alias) {
    exprs = [leadingTypeExpr(alias[1])]
  }
  else if (tag) {
    const [, kind, rest] = tag

    if (kind === 'type' || kind === 'return' || kind === 'as') {
      // @return 可能是 `A, B` 多返回值
      exprs = splitTopLevel(rest).map(leadingTypeExpr)
    }
    else if (kind === 'param' || kind === 'cast') {
      exprs = [leadingTypeExpr(skipName(rest))]
    }
    else if (kind === 'field') {
      const words = rest.split(/\s+/)
      const body = FIELD_SCOPES.has(words[0]) ? skipName(rest) : rest
      exprs = [leadingTypeExpr(skipName(body))]
    }
    else if (kind === 'class') {
      // `X : Parent1, Parent2 描述`，名字本身不算引用，父类后的描述文本丢弃
      const parents = rest.split(':').slice(1).join(':')
      exprs = parents ? splitTopLevel(parents).map(leadingTypeExpr) : []
    }
    else if (kind === 'generic') {
      // `T : Parent, U`，泛型名本身不算引用，只取约束类型
      exprs = splitTopLevel(rest)
        .filter((item) => item.includes(':'))
        .map((item) => leadingTypeExpr(item.slice(item.indexOf(':') + 1).trim()))
    }
    else {
      // alias / enum：名字之后是类型表达式（enum 无类型体）
      // 名字按类型表达式跳过，`dap.RequestListener<T, U>` 的泛型参数不当作引用
      const named = rest.replace(/^\([^)]*\)\s*/, '')
      const name = leadingTypeExpr(named)
      exprs = kind === 'alias' ? [leadingTypeExpr(named.slice(name.length).trim())] : []
    }
  }

  // 行内 `--[[@as T]]` 类型断言可出现在任意代码行
  for (const match of line.matchAll(INLINE_AS_RE)) exprs.push(match[1])

  return exprs
    .map((expr) => expr.replace(/(['"`]).*?\1/g, ' '))
    .flatMap((expr) => [...expr.matchAll(IDENT_RE)].filter((match) => !match[2]).map((match) => match[1]))
    .map((name) => name.replace(/[.\-]+$/, ''))
}

function referencedTypeNamesInFiles(files: string[]) {
  const names = new Set<string>()

  for (const file of files) {
    for (const line of readFileSync(file, 'utf8').split('\n')) {
      for (const name of referencedTypeNames(line)) names.add(name)
    }
  }

  return names
}

function declaredTypeNames(file: string) {
  const names = new Set<string>()

  for (const line of readFileSync(file, 'utf8').split('\n')) {
    const match = line.match(DECL_RE)
    if (match) names.add(match[2])
  }

  return names
}

/** name -> 每个插件根目录下声明它的文件 */
function indexDeclarations(plugins: string[]) {
  const index = new Map<string, Map<string, string[]>>()

  for (const plugin of plugins) {
    for (const file of walkLuaFiles(join(plugin, 'lua'))) {
      for (const name of declaredTypeNames(file)) {
        const byPlugin = index.get(name) ?? new Map<string, string[]>()
        byPlugin.set(plugin, [...(byPlugin.get(plugin) ?? []), file])
        index.set(name, byPlugin)
      }
    }
  }

  return index
}

function resolveSpecTypeFiles() {
  const specFiles = walkLuaFiles(join(CONFIG, 'lua', 'plugins', 'specs'))
  const specNames = referencedTypeNamesInFiles(specFiles)

  // 根项目和 Neovim runtime 已在 workspace / library 中，其声明无需再引入
  const available = new Set<string>()
  for (const file of [...walkLuaFiles(join(CONFIG, 'lua')), ...findNvimRuntime().flatMap(walkLuaFiles)]) {
    for (const name of declaredTypeNames(file)) available.add(name)
  }

  const vendors = scanPluginParent(VENDOR_ROOT).map((path) => resolve(path)).sort()
  const packs = scanPackRoot().map((path) => resolve(path)).sort()
  const vendorSet = new Set(vendors)
  const index = indexDeclarations([...vendors, ...packs])

  const files = new Set<string>()
  const visited = new Set<string>()
  const unresolved = new Set<string>()
  const queue = [...specNames]

  while (queue.length > 0) {
    const name = queue.pop()!
    if (visited.has(name)) continue
    visited.add(name)

    if (available.has(name)) continue

    const byPlugin = index.get(name)
    if (!byPlugin) {
      if (specNames.has(name)) unresolved.add(name)
      continue
    }

    // 同一插件内的分部声明（多文件补充同一 class）全部保留；跨插件重复时优先 vendor
    const plugins = [...byPlugin.keys()].sort((a, b) => Number(vendorSet.has(b)) - Number(vendorSet.has(a)) || a.localeCompare(b))
    const chosen = plugins[0]

    if (plugins.length > 1) {
      const others = plugins.slice(1).flatMap((plugin) => byPlugin.get(plugin)!)
      console.warn(`warn: ${name} 重复声明，使用 ${byPlugin.get(chosen)!.map(toPosix).join(', ')}；忽略 ${others.map(toPosix).join(', ')}`)
    }

    const newFiles = byPlugin.get(chosen)!.filter((file) => !files.has(file))
    for (const file of newFiles) files.add(file)
    queue.push(...referencedTypeNamesInFiles(newFiles))
  }

  const gaps = [...unresolved].filter((name) => !LUALS_BUILTINS.has(name)).sort()

  return {
    specNameCount: [...specNames].filter((name) => index.has(name) || available.has(name)).length,
    files: [...new Set([...files].map((file) => toPosix(resolve(file))))].sort(),
    unresolved: gaps,
  }
}

const specTypes = resolveSpecTypeFiles()

const luarc = {
  runtime: {
    version: 'LuaJIT',
    path: ['lua/?.lua', 'lua/?/init.lua'],
  },
  workspace: {
    library: [...base, ...specTypes.files],
    ignoreDir: ['vendors'],
  },
}

const manifest = { base, projects }

writeFileSync(join(CONFIG, '.luarc.json'), JSON.stringify(luarc, null, 2) + '\n')
writeFileSync(MANIFEST_PATH, JSON.stringify(manifest, null, 2) + '\n')
console.log(
  `.luarc.json: runtime + ${specTypes.files.length} type files for ${specTypes.specNameCount} spec-referenced types; `
    + `.luarc-libraries.json: ${Object.keys(projects).length} vendor projects`,
)

if (specTypes.unresolved.length > 0) {
  console.log(`unresolved spec types: ${specTypes.unresolved.join(', ')}`)
}
