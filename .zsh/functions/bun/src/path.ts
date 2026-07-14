#!/usr/bin/env bun
/**
 * 通用 path 工具，用子命令决定行为。约定: process.stdout.write + process.exit(0)。
 *
 * 用法:
 *   bun run path.ts abs <path>           → 输出绝对路径
 *   bun run path.ts abs <path:line[:col]> → 输出 绝对路径:line[:col]
 */
import { resolve } from 'path'

const argv = process.argv.slice(2)
const sub = argv[0]?.toLowerCase()
const input = argv[1] ?? ''

function out(s: string): void {
  process.stdout.write(s + '\n')
}

function cmdAbs(): void {
  const i = input.indexOf(':')
  if (i < 0) {
    out(resolve(input))
  } else {
    const p = input.slice(0, i)
    const rest = input.slice(i + 1)
    out(resolve(p) + ':' + rest)
  }
}

switch (sub) {
  case 'abs':
    cmdAbs()
    break
  default:
    process.stderr.write(`path.ts: unknown subcommand '${sub}'. Use: abs\n`)
    process.exit(1)
}
process.exit(0)
