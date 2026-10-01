#!/usr/bin/env bun

/**
 * Shared fzf configuration and helpers for bun-based fzf commands.
 */

import { resolve } from 'node:path'
import { die } from './utils'

export const FUNC_DIR = resolve(import.meta.dir, '../..')
export const BUN_SRC = import.meta.dir

const cmdBind = process.env.fzfCmdBind ?? 'ctrl'
const optBind = process.env.fzfOptionBind ?? 'alt'

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1)
}

/** 把 fzf 修饰键转换成紧凑、可辨认的界面提示 */
function modifierHint(modifier: string): string {
  switch (modifier.toLowerCase()) {
    case 'ctrl':
      return '^'
    case 'option':
      return '⌥'
    case 'shift':
      return '⇧'
    default:
      return `${capitalize(modifier)}+`
  }
}

export const fzf = {
  cmd: cmdBind,
  opt: optBind,
  cmdHint: modifierHint(cmdBind),
  // Alt/Option 在所有平台统一显示为同一个物理键符号，实际 fzf 绑定仍是 alt
  optHint: '⌥',

  scrollBinds:
    `${cmdBind}-n:down,${cmdBind}-p:up,ctrl-e:preview-down+preview-down+preview-down+preview-down+preview-down,ctrl-y:preview-up+preview-up+preview-up+preview-up+preview-up`,
  tabToggleDown: 'tab:toggle+down',

  gitPreviewWindow: 'right:75%:border-left:wrap',
  grepoPreviewWindow: 'right:28%:border-left:wrap',
} as const

/** 剪贴板入口脚本：与 zsh 的 cb 共用，后端（OSC52 / pbcopy / ...）在每次复制时现场选择，最终兜底 OSC52 */
export const CLIP_SCRIPT = `${FUNC_DIR}/_actions/clip.sh`

/** 复制命令（shell 字符串，用于 fzf execute 管道） */
export const CLIP_COPY_CMD = `${CLIP_SCRIPT} copy`

export function shellQuote(s: string): string {
  return `'${s.replace(/'/g, '\'\\\'\'')}'`
}

export function assertCmd(name: string): void {
  if (!Bun.which(name)) {
    die(`${name} is required but not installed`)
  }
}

export async function spawnFzf(args: string[], input: string): Promise<number> {
  const proc = Bun.spawn(['fzf', ...args], {
    stdin: Buffer.from(input),
    stdout: 'inherit',
    stderr: 'inherit',
  })
  return proc.exited
}

export async function spawnFzfCapture(
  args: string[],
  input: string,
): Promise<[number, string]> {
  const proc = Bun.spawn(['fzf', ...args], {
    stdin: Buffer.from(input),
    stdout: 'pipe',
    stderr: 'inherit',
  })
  const output = await new Response(proc.stdout).text()
  const code = await proc.exited
  return [code, output.trim()]
}
