/**
 * 图标共享数据源 loader（bun 侧）
 *
 * 数据源：vv-icons.nvim 的 lua/vv-icons/data/*.json，与 nvim 侧共享。
 *
 * 路径解析顺序：
 *   1. $VV_ICONS_DATA_DIR  环境变量（手动覆盖）
 *   2. ~/.config/nvim/vendors/vv-icons.nvim/lua/vv-icons/data  （dev 路径，与 pack.dev 同源）
 *   3. ~/.local/share/nvim/site/pack/core/opt/vv-icons.nvim/lua/vv-icons/data  （nvim 启动时 vim.pack clone 进来的）
 *
 * 语义色 → 256 色 ANSI，orange/purple 升为一等公民。
 */

import { existsSync, readFileSync } from 'node:fs'
import { join } from 'node:path'

function resolveDataDir(): string {
  const env = process.env.VV_ICONS_DATA_DIR
  if (env && existsSync(env)) return env
  const home = process.env.HOME ?? ''
  const candidates = [
    join(home, '.config/nvim/vendors/vv-icons.nvim/lua/vv-icons/data'),
    join(home, '.local/share/nvim/site/pack/core/opt/vv-icons.nvim/lua/vv-icons/data'),
  ]
  for (const p of candidates) {
    if (existsSync(p)) return p
  }
  throw new Error(
    `vv-icons data not found. Tried:\n  ${candidates.join('\n  ')}\n`
    + 'Install via nvim (vim.pack will clone it on next startup), '
    + 'or set VV_ICONS_DATA_DIR to a directory containing files.json/directories.json/etc.',
  )
}

const DATA_DIR = resolveDataDir()

export const COLORS_ANSI = {
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  red: '\x1b[31m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m',
  magenta: '\x1b[35m',
  orange: '\x1b[38;5;208m',
  purple: '\x1b[38;5;135m',
  grey: '\x1b[38;5;245m',
  white: '\x1b[37m',
  reset: '\x1b[0m',
} as const

export type SemColor = Exclude<keyof typeof COLORS_ANSI, 'reset'>

export type IconEntry = {
  glyph?: string
  color?: SemColor
}

export type FileRule = {
  match: string
} & IconEntry

/**
 * 展开单层 brace：`a.{b,c}` → `['a.b','a.c']`；`.env{,.local}` → `['.env','.env.local']`
 * 仅支持 `{a,b,c}` 字面量组，不支持 `*` / `?`；支持嵌套
 */
export function expandBraces(pattern: string): string[] {
  const openIdx = pattern.indexOf('{')
  if (openIdx === -1) return [pattern]

  let depth = 1
  let closeIdx = -1
  for (let i = openIdx + 1; i < pattern.length; i++) {
    const c = pattern[i]
    if (c === '{') depth++
    else if (c === '}') {
      depth--
      if (depth === 0) {
        closeIdx = i
        break
      }
    }
  }
  if (closeIdx === -1) throw new Error(`expandBraces: unmatched '{' in ${pattern}`)

  const prefix = pattern.slice(0, openIdx)
  const suffix = pattern.slice(closeIdx + 1)
  const body = pattern.slice(openIdx + 1, closeIdx)

  const alts: string[] = []
  let buf = ''
  let d2 = 0
  for (const c of body) {
    if (c === ',' && d2 === 0) {
      alts.push(buf)
      buf = ''
      continue
    }
    if (c === '{') d2++
    if (c === '}') d2--
    buf += c
  }
  alts.push(buf)

  const out: string[] = []
  for (const alt of alts) {
    for (const tail of expandBraces(suffix)) {
      out.push(prefix + alt + tail)
    }
  }
  return out
}

function readJSON<T>(name: string): T {
  const path = join(DATA_DIR, `${name}.json`)
  return JSON.parse(readFileSync(path, 'utf8')) as T
}

/** 加载字典型 JSON（git / ui / diagnostics / extensions / filetypes / directories） */
export function loadDict(name: string): Record<string, IconEntry> {
  return readJSON<Record<string, IconEntry>>(name)
}

/**
 * 加载列表型 JSON（files / 含 glob），展开 brace 后以字面量为 key
 * 列表顺序即优先级（列表头优先），重复字面量以靠前的覆盖靠后的
 */
export function loadFiles(name: string): Record<string, IconEntry> {
  const raw = readJSON<FileRule[]>(name)
  const out: Record<string, IconEntry> = {}
  for (let i = raw.length - 1; i >= 0; i--) {
    const { match, glyph, color } = raw[i]
    for (const literal of expandBraces(match)) {
      out[literal] = { glyph, color }
    }
  }
  return out
}

/** 取原始 glyph */
export function glyph(dict: Record<string, IconEntry>, key: string): string {
  return dict[key]?.glyph ?? ''
}

/** 带 ANSI 包裹的 glyph；missing glyph/color 时输出空串（避免出现 "undefined"） */
export function colored(dict: Record<string, IconEntry>, key: string): string {
  const e = dict[key]
  if (!e || !e.glyph) return ''
  const ansi = e.color ? COLORS_ANSI[e.color] : ''
  return `${ansi}${e.glyph}${COLORS_ANSI.reset}`
}
