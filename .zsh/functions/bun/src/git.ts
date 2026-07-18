#!/usr/bin/env bun

/**
 * 输出 git status（机器格式 --porcelain=v1 -z 解析）的列表，供 fzf 使用。
 * 格式：icon \t status(3) \t path，按 path 排序。
 * 约定：process.stdout.write + process.exit(0)，避免 fzf 错行。
 */

import { $ } from 'bun'
import { relative } from 'node:path'
import { COLORS, ICONS } from './shared'

const ICON_STAGED = `${COLORS.Green}${ICONS.git_commit}${COLORS.Reset}`
const ICON_OTHER = `${COLORS.Red}${ICONS.git_merge}${ICONS.git_merge}${COLORS.Reset}`

export async function generateStatusList(): Promise<string> {
  // 机器格式解析：-z 以 NUL 分隔条目，rename/copy 条目为「XY 新名 NUL 旧名 NUL」，
  // 不加引号、不做 quotepath 转义、不含 ` -> ` 箭头，彻底避开文本解析在文件名含空格/
  // 箭头/非 ASCII 时的歧义（故也无需 -c core.quotepath=false）
  const result = await $`git status --porcelain=v1 -z`.nothrow().quiet()
  if (result.exitCode !== 0) return ''

  // -z 下路径一律相对仓库根；旧的文本 --short 相对 cwd，故用 show-prefix 换算回 cwd 相对，
  // 保证 fzf action（在 cwd 下跑 git/编辑器/rm）拿到的路径与原行为一致
  const prefixRes = await $`git rev-parse --show-prefix`.nothrow().quiet()
  const prefix = prefixRes.exitCode === 0 ? prefixRes.stdout.toString().replace(/\r?\n$/, '') : ''

  const tokens = result.stdout.toString().split('\0')
  const rows: [string, string, string][] = []

  for (let i = 0; i < tokens.length; i++) {
    const tok = tokens[i]
    if (!tok) continue

    const status = tok.slice(0, 3)   // XY + 分隔空格，与旧的 slice(0, 3) 一致
    const x = status[0]
    const y = status[1]

    // rename/copy 条目：紧随其后的 NUL token 是旧名，跳过它（path 取新名）
    if (x === 'R' || x === 'C' || y === 'R' || y === 'C') i++

    const rootPath = tok.slice(3)
    const path = prefix ? relative(prefix, rootPath) : rootPath

    const icon = x !== ' ' && x !== '?'
      ? ICON_STAGED
      : ICON_OTHER
    rows.push([icon, status, path])
  }

  rows.sort((a, b) => a[2].localeCompare(b[2], 'en'))
  return rows.map(([icon, status, path]) => `${icon}\t${status}\t${path}`).join('\n')
}

if (import.meta.main) {
  const list = await generateStatusList()
  if (list) process.stdout.write(list + '\n')
  process.exit(0)
}
