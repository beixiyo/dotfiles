#!/usr/bin/env bun

import { readdirSync, statSync, writeFileSync } from 'fs'
import { join, resolve } from 'path'

const CONFIG = resolve(import.meta.dir, '..')
const HOME = process.env.HOME ?? resolve(CONFIG, '..', '..')
const DATA = process.env.XDG_DATA_HOME
  ? join(process.env.XDG_DATA_HOME, 'nvim')
  : join(HOME, '.local', 'share', 'nvim')

const PACK_ROOT = join(DATA, 'site', 'pack')

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
  ...scanPluginParent(join(CONFIG, 'vendors')),
].map(toPosix).sort()

const luarc = {
  workspace: {
    library: ['${3rd}/luv/library', ...libraries],
  },
}

writeFileSync(join(CONFIG, '.luarc.json'), JSON.stringify(luarc, null, 2) + '\n')
console.log(`.luarc.json: ${libraries.length} plugin libraries`)
