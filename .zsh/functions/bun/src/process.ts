#!/usr/bin/env bun

import { $ } from 'bun'
import { confirm } from './shared'

type ProcessCommand = 'kill-by-name' | 'kill-by-port' | 'kill'

function ensureNumeric(value: string, label: string): void {
  if (!/^[0-9]+$/.test(value)) {
    throw new Error(`${label} must be numeric: ${value}`)
  }
}

async function commandExists(name: string): Promise<boolean> {
  return !!Bun.which(name)
}

async function getPidsByName(pattern: string): Promise<string[]> {
  if (!await commandExists('pgrep')) {
    throw new Error('pgrep is required but not installed')
  }

  const result = await $`pgrep -f ${pattern}`.nothrow()
  const stdout = result.stdout.toString()
  const pids = stdout
    .split('\n')
    .map(line => line.trim())
    .filter(Boolean)

  return pids
}

async function getPidsByPort(port: string): Promise<string[]> {
  ensureNumeric(port, 'port')

  if (!await commandExists('lsof')) {
    throw new Error('lsof is required but not installed')
  }

  const result = await $`lsof -ti :${port}`.nothrow()
  const stdout = result.stdout.toString()
  const pids = stdout
    .split('\n')
    .map(line => line.trim())
    .filter(Boolean)

  return pids
}

async function showProcesses(pids: string[]): Promise<void> {
  if (pids.length === 0)
    return

  const result = await $`ps -p ${pids} -o pid,ppid,user,comm,args`.nothrow()
  const stdout = result.stdout.toString().trim()

  if (stdout.length === 0) {
    console.log('no matching processes found')
    return
  }

  console.log('found processes:')
  console.log(stdout)
  console.log()
}

async function sleep(ms: number): Promise<void> {
  await new Promise(resolve => setTimeout(resolve, ms))
}

/** 检测 PID 列表中是否存在非当前用户的进程，需要 sudo 提权 */
async function needsSudo(pids: string[]): Promise<boolean> {
  const uid = process.getuid?.()?.toString()
  if (uid === undefined) return false
  const result = await $`ps -o uid= -p ${pids}`.nothrow()
  const uids = result.stdout.toString().split('\n').map(l => l.trim()).filter(Boolean)
  return uids.some(u => u !== uid)
}

async function filterAlivePids(pids: string[], sudo: boolean): Promise<string[]> {
  const alive: string[] = []
  const prefix = sudo ? ['sudo', 'kill', '-0'] : ['kill', '-0']

  for (const pid of pids) {
    const result = await $`${[...prefix, pid]}`.nothrow()
    if (result.exitCode === 0)
      alive.push(pid)
  }

  return alive
}

async function terminateAndKill(pids: string[], message: string): Promise<void> {
  if (pids.length === 0) {
    console.log('no matching processes found')
    return
  }

  await showProcesses(pids)

  const ok = await confirm(`⚠️  ${message} [y/N] `)
  if (!ok) {
    console.log('cancelled')
    return
  }

  const sudo = await needsSudo(pids)
  if (sudo) console.log('using sudo for processes owned by other users...')

  const killCmd = sudo ? ['sudo', 'kill'] : ['kill']

  await $`${[...killCmd, ...pids]}`.nothrow()
  await sleep(2000)

  let remaining = await filterAlivePids(pids, sudo)

  if (remaining.length > 0) {
    console.log('some processes did not respond to SIGTERM, sending SIGKILL...')
    await $`${[...killCmd, '-9', ...remaining]}`.nothrow()
    await sleep(1000)
  }

  const final = await filterAlivePids(pids, sudo)

  if (final.length > 0) {
    console.log(`failed to kill processes: ${final.join(' ')}`)
  }
  else {
    console.log('processes terminated successfully')
  }
}

async function runKillByName(pattern: string): Promise<void> {
  if (!pattern) {
    console.error('Usage: process.ts kill-by-name <pattern>')
    process.exit(1)
  }

  const pids = await getPidsByName(pattern)
  await terminateAndKill(pids, `Kill all processes matching '${pattern}'?`)
}

async function runKillByPort(port: string): Promise<void> {
  if (!port) {
    console.error('Usage: process.ts kill-by-port <port>')
    process.exit(1)
  }

  const pids = await getPidsByPort(port)
  await terminateAndKill(pids, `Kill processes on port ${port}?`)
}

async function runKill(pids: string[]): Promise<void> {
  if (pids.length === 0) {
    console.error('Usage: process.ts kill <PID1> [PID2] ...')
    process.exit(1)
  }

  for (const pid of pids)
    ensureNumeric(pid, 'PID')

  await terminateAndKill(pids, `Kill processes: ${pids.join(' ')}?`)
}

function printUsage(): void {
  console.error(
    [
      'Usage:',
      '  process.ts kill-by-name <pattern>',
      '  process.ts kill-by-port <port>',
      '  process.ts kill <PID1> [PID2] ...',
    ].join('\n'),
  )
}

async function main() {
  const [, , sub, ...rest] = process.argv

  if (!sub || sub === '-h' || sub === '--help') {
    printUsage()
    process.exit(sub ? 0 : 1)
  }

  const cmd = sub as ProcessCommand

  try {
    switch (cmd) {
      case 'kill-by-name':
        await runKillByName(rest[0] ?? '')
        break
      case 'kill-by-port':
        await runKillByPort(rest[0] ?? '')
        break
      case 'kill': {
        await runKill(rest)
        break
      }
      default:
        printUsage()
        process.exit(1)
    }
    process.exit(0)
  }
  catch (err) {
    console.error((err as Error).message)
    process.exit(1)
  }
}

main()
