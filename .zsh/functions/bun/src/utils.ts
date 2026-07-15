/**
 * Shared utilities for bun scripts: logging, assertions, process helpers.
 */

type BunColor = (value: string, format: 'ansi-256') => string | null

const bunColor = (Bun as typeof Bun & { color?: BunColor }).color
const ansiEnabled = process.env.NO_COLOR === undefined
  && (Bun.enableANSIColors ?? process.stderr.isTTY === true)

function ansi(value: string, fallback: string): string {
  if (!ansiEnabled) return ''
  if (typeof bunColor !== 'function') return fallback
  return bunColor(value, 'ansi-256') ?? fallback
}

export const C = {
  red: ansi('#f7768e', '\x1b[31m'),
  green: ansi('#9ece6a', '\x1b[32m'),
  yellow: ansi('#e0af68', '\x1b[33m'),
  cyan: ansi('#7dcfff', '\x1b[36m'),
  blue: ansi('#7aa2f7', '\x1b[34m'),
  dim: ansiEnabled ? '\x1b[2m' : '',
  bold: ansiEnabled ? '\x1b[1m' : '',
  reset: ansiEnabled ? '\x1b[0m' : '',
} as const

export function color(text: string, value: string): string {
  const prefix = ansi(value, '')
  return prefix
    ? `${prefix}${text}${C.reset}`
    : text
}

export function log(msg: string): void {
  process.stderr.write(`${C.cyan}▸${C.reset} ${msg}\n`)
}

export function logOk(msg: string): void {
  process.stderr.write(`${C.green}✔${C.reset} ${msg}\n`)
}

export function logWarn(msg: string): void {
  process.stderr.write(`${C.yellow}⚠${C.reset} ${msg}\n`)
}

export function logErr(msg: string): void {
  process.stderr.write(`${C.red}✘${C.reset} ${msg}\n`)
}

export function logCommand(cmd: string[]): void {
  const [executable, ...args] = cmd
  const suffix = args.length > 0
    ? ` ${args.join(' ')}`
    : ''
  process.stderr.write(`${C.green}$${C.reset} ${C.blue}${executable}${C.reset}${suffix}\n`)
}

export function die(msg: string, code = 1): never {
  logErr(msg)
  process.exit(code)
}

export function assertCmd(name: string): void {
  if (!Bun.which(name)) {
    die(`${name} is required but not installed`)
  }
}

export function hasCmd(name: string): boolean {
  return !!Bun.which(name)
}
