#!/usr/bin/env bun

import { stat } from 'node:fs/promises'
import { $ } from 'bun'
import { confirm } from './shared'

type FileOpsCommand = 'rmr' | 'rme'

async function pathExistsDir(path: string): Promise<boolean> {
  try {
    const s = await stat(path)
    return s.isDirectory()
  }
  catch {
    return false
  }
}

async function runRmr(root: string, patterns: string[]) {
  if (!root || patterns.length === 0) {
    console.error('Usage: rmr <root> <pattern1> [pattern2] ...')
    process.exit(1)
  }

  if (!await pathExistsDir(root)) {
    console.error(`directory not found: ${root}`)
    process.exit(1)
  }

  console.log(`searching ${root} for: ${patterns.join(' ')}`)

  const targets = new Set<string>()

  for (const pattern of patterns) {
    const result = await $`fd --glob ${pattern} ${root} --unrestricted --color never`.nothrow()
    const stdout = result.stdout.toString()
    for (const line of stdout.split('\n')) {
      const trimmed = line.trim()
      if (trimmed.length > 0)
        targets.add(trimmed)
    }
  }

  const list = Array.from(targets)

  if (list.length === 0) {
    console.log('no matching files found')
    return
  }

  console.log(`will delete ${list.length} item(s):`)
  for (const f of list)
    console.log(`   ${f}`)
  console.log()

  const ok = await confirm('confirm delete? [y/N] ')
  if (!ok) {
    console.log('cancelled')
    return
  }

  for (const f of list) {
    console.log(`   rm: ${f}`)
    await $`rm -rf ${f}`.nothrow()
  }
  console.log('done')
}

async function runRme(keepNames: string[]) {
  if (keepNames.length === 0) {
    console.error('Usage: rme <keep1> [keep2] ...')
    process.exit(1)
  }

  console.log('will delete everything in current directory except:')
  for (const name of keepNames)
    console.log(`   + ${name}`)
  console.log()

  const ok = await confirm('confirm delete? [y/N] ')
  if (!ok) {
    console.log('cancelled')
    return
  }

  const args: string[] = ['.', '-mindepth', '1', '-maxdepth', '1']
  for (const name of keepNames) {
    args.push('!', '-name', name)
  }

  await $`find ${args} -exec rm -rf {} +`.nothrow()
  console.log('done')
}

function printUsage() {
  console.error(
    [
      'Usage:',
      '  file-ops.ts rmr <root> <pattern1> [pattern2] ...',
      '  file-ops.ts rme <keep1> [keep2] ...',
    ].join('\n'),
  )
}

async function main() {
  const [, , sub, ...rest] = process.argv

  if (!sub || sub === '-h' || sub === '--help') {
    printUsage()
    process.exit(sub ? 0 : 1)
  }

  const cmd = sub as FileOpsCommand

  switch (cmd) {
    case 'rmr': {
      const [root, ...patterns] = rest
      await runRmr(root, patterns)
      break
    }
    case 'rme':
      await runRme(rest)
      break
    default:
      printUsage()
      process.exit(1)
  }
  process.exit(0)
}

main()

