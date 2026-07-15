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
import { log, logCommand, logErr } from './utils'

type DevCommand = 'd' | 'b' | 'i' | 't'

type PackageManager = 'pnpm' | 'bun' | 'yarn' | 'npm'

async function exists(path: string): Promise<boolean> {
  return Bun.file(path).exists()
}

async function detectPm(cwd: string): Promise<PackageManager> {
  const path = (name: string) => `${cwd}/${name}`

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

/** 运行命令并在失败时退出 */
async function run(cwd: string, cmd: string[]): Promise<void> {
  logCommand(cmd)
  const code = await runWithTty(cwd, cmd)
  if (code !== 0) process.exit(code)
}

async function runDev(cwd: string, args: string[]) {
  if (await exists(`${cwd}/package.json`)) {
    const pm = await detectPm(cwd)
    log('starting dev server...')
    await run(cwd, [...pmRunCmd(pm, 'dev'), ...args])
    return
  }

  if (await exists(`${cwd}/go.mod`)) {
    log('running Go project...')
    await run(cwd, ['go', 'run', '.', ...args])
    return
  }

  if (await exists(`${cwd}/Cargo.toml`)) {
    log('running Rust project...')
    await run(cwd, ['cargo', 'run', ...(args.length > 0 ? ['--', ...args] : [])])
    return
  }

  if (await exists(`${cwd}/pyproject.toml`) || await exists(`${cwd}/uv.lock`)) {
    const entry = await exists(`${cwd}/main.py`)
      ? 'main.py'
      : await exists(`${cwd}/app.py`)
        ? 'app.py'
        : null

    if (args.length === 0 && !entry) {
      logErr('Python has no universal dev command; use: d <command> [args...]')
      process.exit(1)
    }

    log('running Python project...')
    await run(cwd, ['uv', 'run', ...(args.length > 0 ? args : [entry!])])
    return
  }

  if (await exists(`${cwd}/pom.xml`)) {
    log('starting Java dev server...')
    await run(cwd, [
      'nodemon', '-w', './controller/**/*', '-e', 'java', '-x', 'mvn spring-boot:run',
    ])
    return
  }

  if (await exists(`${cwd}/pubspec.yaml`)) {
    log('starting Flutter...')
    await run(cwd, ['flutter', 'run'])
    return
  }

  logErr('no supported project file found')
  process.exit(1)
}

async function runBuild(cwd: string, args: string[]) {
  if (await exists(`${cwd}/package.json`)) {
    const pm = await detectPm(cwd)
    log('building Node.js project...')
    await run(cwd, [...pmRunCmd(pm, 'build'), ...args])
    return
  }

  if (await exists(`${cwd}/go.mod`)) {
    log('building Go project...')
    await run(cwd, ['go', 'build', ...args, './...'])
    return
  }

  if (await exists(`${cwd}/Cargo.toml`)) {
    log('building Rust project...')
    await run(cwd, ['cargo', 'build', ...args])
    return
  }

  if (await exists(`${cwd}/pyproject.toml`) || await exists(`${cwd}/uv.lock`)) {
    log('building Python distributions...')
    await run(cwd, ['uv', 'build', ...args])
    return
  }

  if (await exists(`${cwd}/pom.xml`)) {
    log('building Java project...')
    await run(cwd, ['mvn', 'clean', 'package'])
    return
  }

  if (await exists(`${cwd}/pubspec.yaml`)) {
    log('building Flutter project...')
    await run(cwd, ['flutter', 'clean'])
    await run(cwd, ['flutter', 'build'])
    return
  }

  logErr('no supported project file found')
  process.exit(1)
}

async function runInstall(cwd: string, args: string[]) {
  if (await exists(`${cwd}/package.json`)) {
    const pm = await detectPm(cwd)
    log(args.length > 0
      ? `installing: ${args.join(' ')}`
      : 'installing dependencies...')
    await run(cwd, pmInstallCmd(pm, args))
    return
  }

  if (await exists(`${cwd}/go.mod`)) {
    log(args.length > 0
      ? `adding Go modules: ${args.join(' ')}`
      : 'downloading Go modules...')
    await run(cwd, args.length > 0
      ? ['go', 'get', ...args]
      : ['go', 'mod', 'download'])
    return
  }

  if (await exists(`${cwd}/Cargo.toml`)) {
    log(args.length > 0
      ? `adding Rust crates: ${args.join(' ')}`
      : 'fetching Rust crates...')
    await run(cwd, args.length > 0
      ? ['cargo', 'add', ...args]
      : ['cargo', 'fetch'])
    return
  }

  if (await exists(`${cwd}/pyproject.toml`) || await exists(`${cwd}/uv.lock`)) {
    log(args.length > 0
      ? `adding Python packages: ${args.join(' ')}`
      : 'syncing Python environment...')
    await run(cwd, args.length > 0
      ? ['uv', 'add', ...args]
      : ['uv', 'sync'])
    return
  }

  if (await exists(`${cwd}/pom.xml`)) {
    log('installing Maven dependencies...')
    await run(cwd, ['mvn', 'clean', 'install'])
    return
  }

  if (await exists(`${cwd}/pubspec.yaml`)) {
    if (args.length > 0) {
      log(`adding: ${args.join(' ')}`)
      await run(cwd, ['flutter', 'pub', 'add', ...args])
    }
    else {
      log('fetching Flutter dependencies...')
      await run(cwd, ['flutter', 'pub', 'get'])
    }
    return
  }

  logErr('no supported project file found')
  process.exit(1)
}

async function runTest(cwd: string, args: string[]) {
  if (await exists(`${cwd}/package.json`)) {
    const pm = await detectPm(cwd)
    log('running tests...')
    await run(cwd, [...pmRunCmd(pm, 'test'), ...args])
    return
  }

  if (await exists(`${cwd}/go.mod`)) {
    log('testing Go project...')
    await run(cwd, ['go', 'test', ...args, './...'])
    return
  }

  if (await exists(`${cwd}/Cargo.toml`)) {
    log('testing Rust project...')
    await run(cwd, ['cargo', 'test', ...args])
    return
  }

  if (await exists(`${cwd}/pyproject.toml`) || await exists(`${cwd}/uv.lock`)) {
    log('testing Python project...')
    await run(cwd, ['uv', 'run', 'pytest', ...args])
    return
  }

  if (await exists(`${cwd}/pom.xml`)) {
    log('running Maven tests...')
    await run(cwd, ['mvn', 'test'])
    return
  }

  if (await exists(`${cwd}/pubspec.yaml`)) {
    log('running Flutter tests...')
    await run(cwd, ['flutter', 'test'])
    return
  }

  logErr('no supported project file found')
  process.exit(1)
}

function printUsage() {
  console.error(
    [
      'Usage:',
      '  dev.ts d [args...]  # start dev server',
      '  dev.ts b [args...]  # build project',
      '  dev.ts i [pkg...]   # install dependencies',
      '  dev.ts t [args...]  # run tests',
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
      await runDev(cwd, rest)
      break
    case 'b':
      await runBuild(cwd, rest)
      break
    case 'i':
      await runInstall(cwd, rest)
      break
    case 't':
      await runTest(cwd, rest)
      break
    default:
      printUsage()
      process.exit(1)
  }
  process.exit(0)
}

main()
