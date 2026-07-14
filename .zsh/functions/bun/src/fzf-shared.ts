#!/usr/bin/env bun

/**
 * Shared fzf configuration and helpers for bun-based fzf commands.
 */

import { resolve } from 'node:path'
import { readFileSync } from 'node:fs'
import { die } from './utils'

export const FUNC_DIR = resolve(import.meta.dir, '../..')
export const BUN_SRC = import.meta.dir

const cmdBind = process.env.fzfCmdBind ?? 'ctrl'
const optBind = process.env.fzfOptionBind ?? 'alt'

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1)
}

export const fzf = {
  cmd: cmdBind,
  opt: optBind,
  optLabel: capitalize(process.env.optionKey ?? 'alt'),

  scrollBinds: `${cmdBind}-n:down,${cmdBind}-p:up,ctrl-e:preview-down+preview-down+preview-down+preview-down+preview-down,ctrl-y:preview-up+preview-up+preview-up+preview-up+preview-up`,
  tabToggleDown: 'tab:toggle+down',

  gitPreviewWindow: 'right:75%:border-left:wrap',
  grepoPreviewWindow: 'right:28%:border-left:wrap',
} as const

function isWSL(): boolean {
  if (process.env.WSL_DISTRO_NAME || process.env.WSLENV) return true
  try { return /microsoft/i.test(readFileSync('/proc/version', 'utf8')) }
  catch { return false }
}

export function detectClipCopy(): string {
  if (Bun.which('pbcopy')) return 'pbcopy'
  if (Bun.which('wl-copy')) return 'wl-copy'
  if (isWSL()) return 'clip.exe'
  if (Bun.which('xclip')) return 'xclip -selection clipboard'
  if (Bun.which('xsel')) return 'xsel --clipboard --input'
  return 'cat'
}

export function shellQuote(s: string): string {
  return `'${s.replace(/'/g, "'\\''")}'`
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
