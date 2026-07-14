#!/usr/bin/env bun

/**
 * 从 stdin 读 rg 输出（path:line:column:content），每行前加文件类型图标，写回 stdout。
 * 格式：color+icon+reset + \x01 + 原行，约定 process.stdout.write + process.exit(0)。
 */

import { getFileIconColored } from './shared'

const FIELD_SEP = '\x01'

async function main(): Promise<void> {
  const chunks: Buffer[] = []
  for await (const chunk of process.stdin) chunks.push(chunk)

  const raw = Buffer.concat(chunks).toString('utf8')
  const lines = raw.split('\n').filter(Boolean)

  for (const line of lines) {
    const idx = line.indexOf(':')
    const path = idx >= 0 ? line.slice(0, idx) : line
    const iconColored = getFileIconColored(path, false)
    process.stdout.write(`${iconColored}${FIELD_SEP}${line}\n`)
  }
  process.exit(0)
}

main()
