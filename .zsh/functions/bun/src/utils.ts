/**
 * Shared utilities for bun scripts: logging, assertions, process helpers.
 */

export const C = {
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  cyan: '\x1b[36m',
  dim: '\x1b[2m',
  bold: '\x1b[1m',
  reset: '\x1b[0m',
} as const

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
