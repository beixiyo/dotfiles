#!/usr/bin/env bun

/**
 * Dev helper for zsh: d / b / i / t
 *
 * 设计用法（在 zsh 中）：
 *
 *   d() { ~/.zsh/functions/bun/dev.ts d "$@"; }
 *   b() { ~/.zsh/functions/bun/dev.ts b "$@"; }
 *   i() { ~/.zsh/functions/bun/dev.ts i "$@"; }
 *   t() { ~/.zsh/functions/bun/dev.ts t "$@"; }
 *
 * 行为与原 `dev.zsh` 尽量保持一致。
 */

import { runWithTty } from './shared'

type DevCommand = 'd' | 'b' | 'i' | 't'

type PackageManager = 'pnpm' | 'bun' | 'yarn' | 'npm'

async function detectPm(cwd: string): Promise<PackageManager> {
  const path = (name: string) => `${cwd}/${name}`

  const exists = async (p: string) => {
    try {
      const stat = await Bun.file(p).stat()
      return stat.size >= 0
    }
    catch {
      return false
    }
  }

  if (await exists(path('pnpm-lock.yaml'))) {
    if (Bun.which('pnpm'))
      return 'pnpm'
  }
  if ((await exists(path('bun.lockb'))) || (await exists(path('bun.lock')))) {
    if (Bun.which('bun'))
      return 'bun'
  }
  if (await exists(path('yarn.lock'))) {
    if (Bun.which('yarn'))
      return 'yarn'
  }

  for (const p of ['pnpm', 'bun', 'yarn'] as const) {
    if (Bun.which(p))
      return p
  }

  return 'npm'
}

/**
 * 构建 PM 运行脚本命令：(pm, script) → 命令数组
 *
 * 统一使用 `<pm> run <script>`，四个 PM（npm / pnpm / yarn / bun）都兼容
 */
function pmRunCmd(pm: PackageManager, script: string): string[] {
  return [pm, 'run', script]
}

/** 构建 PM 安装命令 */
function pmInstallCmd(pm: PackageManager, pkgs: string[]): string[] {
  if (pkgs.length === 0) return [pm, 'install']
  // npm 用 install，其他用 add
  if (pm === 'npm') return ['npm', 'install', ...pkgs]
  return [pm, 'add', ...pkgs]
}

/** 格式化命令用于日志输出 */
function fmtCmd(cmd: string[]): string {
  return '+ ' + cmd.join(' ')
}

/** 运行命令并在失败时退出 */
async function run(cwd: string, cmd: string[]): Promise<void> {
  console.log(fmtCmd(cmd))
  const code = await runWithTty(cwd, cmd)
  if (code !== 0) process.exit(code)
}

async function runDev(cwd: string) {
  if (await Bun.file(`${cwd}/package.json`).exists()) {
    const pm = await detectPm(cwd)
    console.log('starting dev server...')
    await run(cwd, pmRunCmd(pm, 'dev'))
    return
  }

  if (await Bun.file(`${cwd}/pom.xml`).exists()) {
    console.log('starting Java dev server...')
    await run(cwd, [
      'nodemon', '-w', './controller/**/*', '-e', 'java', '-x', 'mvn spring-boot:run',
    ])
    return
  }

  if (await Bun.file(`${cwd}/pubspec.yaml`).exists()) {
    console.log('starting Flutter...')
    await run(cwd, ['flutter', 'run'])
    return
  }

  console.error('no supported project file found')
  process.exit(1)
}

async function runBuild(cwd: string) {
  if (await Bun.file(`${cwd}/package.json`).exists()) {
    const pm = await detectPm(cwd)
    console.log('building Node.js project...')
    await run(cwd, pmRunCmd(pm, 'build'))
    return
  }

  if (await Bun.file(`${cwd}/pom.xml`).exists()) {
    console.log('building Java project...')
    await run(cwd, ['mvn', 'clean', 'package'])
    return
  }

  if (await Bun.file(`${cwd}/pubspec.yaml`).exists()) {
    console.log('building Flutter project...')
    await run(cwd, ['flutter', 'clean'])
    await run(cwd, ['flutter', 'build'])
    return
  }

  console.error('no supported project file found')
  process.exit(1)
}

async function runInstall(cwd: string, args: string[]) {
  if (await Bun.file(`${cwd}/package.json`).exists()) {
    const pm = await detectPm(cwd)
    console.log(args.length > 0
      ? `installing: ${args.join(' ')}`
      : 'installing dependencies...')
    await run(cwd, pmInstallCmd(pm, args))
    return
  }

  if (await Bun.file(`${cwd}/pom.xml`).exists()) {
    console.log('installing Maven dependencies...')
    await run(cwd, ['mvn', 'clean', 'install'])
    return
  }

  if (await Bun.file(`${cwd}/pubspec.yaml`).exists()) {
    if (args.length > 0) {
      console.log(`adding: ${args.join(' ')}`)
      await run(cwd, ['flutter', 'pub', 'add', ...args])
    }
    else {
      console.log('fetching Flutter dependencies...')
      await run(cwd, ['flutter', 'pub', 'get'])
    }
    return
  }

  console.error('no supported project file found')
  process.exit(1)
}

async function runTest(cwd: string) {
  if (await Bun.file(`${cwd}/package.json`).exists()) {
    const pm = await detectPm(cwd)
    console.log('running tests...')
    await run(cwd, pmRunCmd(pm, 'test'))
    return
  }

  if (await Bun.file(`${cwd}/pom.xml`).exists()) {
    console.log('running Maven tests...')
    await run(cwd, ['mvn', 'test'])
    return
  }

  if (await Bun.file(`${cwd}/pubspec.yaml`).exists()) {
    console.log('running Flutter tests...')
    await run(cwd, ['flutter', 'test'])
    return
  }

  console.error('no supported project file found')
  process.exit(1)
}

function printUsage() {
  console.error(
    [
      'Usage:',
      '  dev.ts d [args...]  # start dev server',
      '  dev.ts b            # build project',
      '  dev.ts i [pkg...]   # install dependencies',
      '  dev.ts t            # run tests',
    ].join('\n'),
  )
}

async function main() {
  const [, , sub, ...rest] = process.argv
  const cwd = process.cwd()

  if (!sub || sub === '-h' || sub === '--help') {
    printUsage()
    process.exit(sub
      ? 0
      : 1)
  }

  const cmd = sub as DevCommand

  switch (cmd) {
    case 'd':
      await runDev(cwd)
      break
    case 'b':
      await runBuild(cwd)
      break
    case 'i':
      await runInstall(cwd, rest)
      break
    case 't':
      await runTest(cwd)
      break
    default:
      printUsage()
      process.exit(1)
  }
  process.exit(0)
}

main()
