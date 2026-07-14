#!/usr/bin/env bun

/**
 * 输出带颜色图标的文件/目录列表，供 fzf ff() 使用
 * 格式：color+icon+reset + \x01 + path（\x01 作分隔使图标列仅 1 字符宽），约定 process.stdout.write + process.exit(0)
 */

import { spawnSync } from 'child_process'
import { join } from 'path'
import { existsSync, statSync } from 'fs'
import { getFileIconColored } from './shared'

const HAS_FD = !!Bun.which('fd')

const FIELD_SEP = '\x01'

type FilterType = 'd' | 'f' | 'a'

function listFiles(dir: string, typeFilter: FilterType, noIgnore: boolean): string[] {
  const dirArg = dir === '.' ? '.' : dir
  const args: string[] = ['.', dirArg, '--color', 'never', '--follow', '--hidden', '--no-ignore-parent', '--exclude', '.git']
  if (noIgnore) args.push('--no-ignore-vcs')

  if (typeFilter === 'd') args.push('--type', 'd')
  else if (typeFilter === 'f') args.push('--type', 'f')

  const result = HAS_FD
    ? spawnSync('fd', args, { encoding: 'utf8' })
    : spawnSync('find', [dirArg, '-not', '-path', '*/.git/*', '-not', '-path', '*/.git'], { encoding: 'utf8' })

  if (result.status !== 0 || !result.stdout) return []
  const raw = result.stdout.trim()
  if (!raw) return []

  let lines = raw.split('\n').filter(Boolean)
  if (!HAS_FD) {
    if (typeFilter === 'd') lines = lines.filter(p => statSync(p).isDirectory())
    else if (typeFilter === 'f') lines = lines.filter(p => statSync(p).isFile())
  }

  return lines.sort((a, b) => a.localeCompare(b, 'en'))
}

function main(): void {
  let dir = '.'
  let typeFilter: FilterType = 'a'
  let noIgnore = false
  const argv = process.argv.slice(2)

  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--dir' && argv[i + 1]) {
      dir = argv[++i]
    } else if (argv[i] === '--type' && argv[i + 1]) {
      const t = argv[++i]
      if (t === 'd' || t === 'f' || t === 'a') typeFilter = t
    } else if (argv[i] === '--no-ignore') {
      noIgnore = true
    }
  }

  const lines = listFiles(dir, typeFilter, noIgnore)
  const cwd = process.cwd()

  for (const line of lines) {
    const full = join(cwd, line)
    const isDir = existsSync(full) && statSync(full).isDirectory()
    const iconColored = getFileIconColored(line, isDir)
    process.stdout.write(`${iconColored}${FIELD_SEP}${line}\n`)
  }
  process.exit(0)
}

main()
