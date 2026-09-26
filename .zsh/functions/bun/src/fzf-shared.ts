#!/usr/bin/env bun

/**
 * Shared fzf configuration and helpers for bun-based fzf commands.
 */

import { readFileSync } from 'node:fs'
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

function isWSL(): boolean {
  if (process.env.WSL_DISTRO_NAME || process.env.WSLENV) return true
  try {
    return /microsoft/i.test(readFileSync('/proc/version', 'utf8'))
  }
  catch {
    return false
  }
}

/** tmux 是否存在经 ssh attach 的客户端（客户端进程父链为 sshd）：剪贴板应跟随对端 */
function isTmuxSshAttached(): boolean {
  if (!process.env.TMUX) return false

  const clients = Bun.spawnSync(['tmux', 'list-clients', '-F', '#{client_pid}'], {
    stdout: 'pipe',
    stderr: 'ignore',
  })
  if (!clients.success) return false

  for (const line of clients.stdout.toString().split('\n')) {
    const parentId = psField('ppid=', line.trim())
    if (!parentId) continue
    if (psField('comm=', parentId).startsWith('sshd')) return true
  }
  return false
}

/** 读取进程字段（ps -o <field>= -p <pid>），失败返回空串 */
function psField(field: string, pid: string): string {
  if (!/^\d+$/.test(pid)) return ''
  const r = Bun.spawnSync(['ps', '-o', field, '-p', pid], { stdout: 'pipe', stderr: 'ignore' })
  return r.success ? r.stdout.toString().trim() : ''
}

export function detectClipCopy(): string {
  // 本地 tmux 被 ssh attach，或 ssh 登录无 GUI 的远程机：
  // OSC52 会被 tmux 广播给所有客户端，各端写各的剪贴板，优先于本地工具
  if (
    isTmuxSshAttached()
    || (process.env.SSH_TTY && !process.env.DISPLAY && !process.env.WAYLAND_DISPLAY)
  ) {
    return `${FUNC_DIR}/_actions/osc52.sh copy`
  }
  if (Bun.which('pbcopy')) return 'pbcopy'
  if (Bun.which('wl-copy')) return 'wl-copy'
  if (isWSL()) return 'clip.exe'
  if (Bun.which('xclip')) return 'xclip -selection clipboard'
  if (Bun.which('xsel')) return 'xsel --clipboard --input'
  return 'cat'
}

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
