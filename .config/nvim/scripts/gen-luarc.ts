#!/usr/bin/env bun

import { readFileSync, readdirSync, statSync, writeFileSync } from 'fs'
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
  try { return statSync(p).isDirectory() }
  catch { return false }
}

function scanPluginParent(dir: string) {
  if (!isDir(dir)) return [] as string[]
  return readdirSync(dir)
    .filter((name: string) => isDir(join(dir, name, 'lua')))
    .map((name: string) => join(dir, name))
}

function walkLuaFiles(dir: string): string[] {
  if (!isDir(dir)) return []

  return readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    const path = join(dir, entry.name)
    if (entry.isDirectory()) return walkLuaFiles(path)
    return entry.isFile() && entry.name.endsWith('.lua') ? [path] : []
  })
}

function moduleNames(plugin: string) {
  const luaDir = join(plugin, 'lua')
  if (!isDir(luaDir)) return []

  return readdirSync(luaDir, { withFileTypes: true })
    .filter(entry => entry.isDirectory() || entry.name.endsWith('.lua'))
    .map(entry => entry.isDirectory()
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
  return readdirSync(PACK_ROOT).flatMap((group: string) =>
    ['opt', 'start'].flatMap(type =>
      scanPluginParent(join(PACK_ROOT, group, type))
    )
  )
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
].map(path => resolve(path)).sort()

const providers = new Map<string, string>()
for (const library of libraries) {
  for (const moduleName of moduleNames(library)) {
    if (!providers.has(moduleName)) providers.set(moduleName, library)
  }
}

const projects = Object.fromEntries(
  scanPluginParent(VENDOR_ROOT).map(project => {
    const dependencies = [...requiredModules(project)]
      .map(moduleName => providers.get(moduleName))
      .filter((dependency): dependency is string =>
        dependency !== undefined && dependency !== project
      )
      .map(toPosix)
      .sort()

    return [toPosix(resolve(project)), [...new Set(dependencies)]]
  })
)

const base = [
  '${3rd}/luv/library',
  ...findNvimRuntime().map(path => toPosix(resolve(path))),
]

const luarc = {
  runtime: {
    version: 'LuaJIT',
    path: ['lua/?.lua', 'lua/?/init.lua'],
  },
  workspace: {
    library: base,
    ignoreDir: ['vendors'],
  },
}

const manifest = { base, projects }

writeFileSync(join(CONFIG, '.luarc.json'), JSON.stringify(luarc, null, 2) + '\n')
writeFileSync(MANIFEST_PATH, JSON.stringify(manifest, null, 2) + '\n')
console.log(
  `.luarc.json: Neovim runtime only; `
  + `.luarc-libraries.json: ${Object.keys(projects).length} vendor projects`
)
