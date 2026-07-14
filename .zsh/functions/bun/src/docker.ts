#!/usr/bin/env bun

/**
 * Docker 相关逻辑：Zsh 胶水层调用，Bun 负责列表生成、dispatch、Docker Hub API。
 *
 * 子命令：
 *   dinfo <repo> <tag> [arch] [os]   - Docker Hub v2 仓库/tag/镜像信息
 *   list                             - dd 用：容器 + 镜像（类型\t图标\tID\t...）
 *   list containers [--all]          - dex/dlogs/dcp 用：容器列表
 *   dispatch <action> [line...]      - 解析选中行并执行 docker 操作（logs/exec/copy/stop/run/restart/delete/image）
 */

import { COLORS, ICONS } from './shared'

// 容器 / 镜像图标（Nerd Font），带颜色；格式为 类型\t图标\tID\t...，dispatch 用 cut -f3 取 ID
const ICON_CONTAINER = `${COLORS.Cyan}${ICONS.container}${COLORS.Reset}`
const ICON_IMAGE = `${COLORS.Blue}${ICONS.docker}${COLORS.Reset}`

// 不用 table：table 会对齐列用空格填充，导致 split('\t') 后 parts[2] 整行当 ID
const DOCKER_PS_FORMAT = '{{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Names}}'
const DOCKER_PS_RUNNING = '{{.ID}}\t{{.Image}}\t{{.Names}}'
const DOCKER_IMAGES_FORMAT = '{{.ID}}\t{{.Repository}}\t{{.Tag}}\t{{.Size}}'
const DOCKER_CMD = process.env.DOCKER_USE_SUDO === '1'
  ? ['sudo', 'docker']
  : ['docker']

async function runDocker(args: string[]): Promise<string> {
  const proc = Bun.spawn([...DOCKER_CMD, ...args], {
    stdout: 'pipe',
    stderr: 'pipe',
  })
  const out = await new Response(proc.stdout).text()
  const err = await new Response(proc.stderr).text()
  const code = await proc.exited
  if (code !== 0 && err)
    process.stderr.write(err)
  return out
}

/** 需 TTY 的 docker 命令（exec、logs -f），stdio 继承当前进程 */
async function runDockerTty(args: string[]): Promise<number> {
  const proc = Bun.spawn([...DOCKER_CMD, ...args], {
    stdio: ['inherit', 'inherit', 'inherit'],
  })
  return await proc.exited
}

function writeLine(line: string) {
  process.stdout.write(line + '\n')
}

/** 按优先级检测可用剪贴板命令，返回 spawn 参数数组 */
function resolveClipCmd(): string[] | null {
  const candidates: [string, string[]][] = [
    ['pbcopy', ['pbcopy']],
    ['clip.exe', ['clip.exe']],
    ['wl-copy', ['wl-copy']],
    ['xclip', ['xclip', '-selection', 'clipboard']],
    ['xsel', ['xsel', '--clipboard', '--input']],
  ]
  for (const [bin, cmd] of candidates) {
    if (Bun.which(bin)) return cmd
  }
  return null
}

// --- list: 供 dd / dex / dlogs / dcp 的 fzf 数据源 ---

async function listDd() {
  const psOut = await runDocker(['ps', '-a', '--format', DOCKER_PS_FORMAT])
  const imgOut = await runDocker(['images', '--format', DOCKER_IMAGES_FORMAT])
  writeLine('=== CONTAINERS ===')
  for (const line of psOut.split('\n').filter(Boolean))
    writeLine('C\t' + ICON_CONTAINER + '\t' + line)
  writeLine('')
  writeLine('=== IMAGES ===')
  for (const line of imgOut.split('\n').filter(Boolean))
    writeLine('I\t' + ICON_IMAGE + '\t' + line)
  process.exit(0)
}

async function listContainers(all: boolean) {
  const args = all
    ? ['ps', '-a', '--format', DOCKER_PS_FORMAT]
    : ['ps', '--format', DOCKER_PS_RUNNING]
  const out = await runDocker(args)
  for (const line of out.split('\n').filter(Boolean))
    writeLine(line)
  process.exit(0)
}

// --- dispatch: 解析 fzf 选中行（类型\t图标\tID\t...）并执行 docker 操作 ---

function parseLines(lines: string[]): { cids: string[]; iids: string[] } {
  const cids: string[] = []
  const iids: string[] = []
  for (const line of lines) {
    if (!line.trim())
      continue
    const parts = line.split('\t')
    if (parts.length < 3)
      continue
    const type = parts[0]
    const id = parts[2]
    if (!id)
      continue
    if (type === 'C')
      cids.push(id)
    else if (type === 'I')
      iids.push(id)
  }
  return { cids, iids }
}

async function dispatch(action: string, lines: string[]) {
  const { cids, iids } = parseLines(lines)
  const firstCid = cids[0]
  const firstId = firstCid || iids[0]

  switch (action) {
    case 'logs':
      if (firstCid) {
        const code = await runDockerTty(['logs', '-f', firstCid])
        process.exit(code ?? 1)
      }
      break
    case 'exec':
      if (firstCid) {
        let code = await runDockerTty(['exec', '-it', firstCid, 'bash'])
        if (code !== 0)
          code = await runDockerTty(['exec', '-it', firstCid, 'sh'])
        process.exit(code ?? 1)
      }
      break
    case 'copy':
      if (firstId) {
        const clipCmd = resolveClipCmd()
        if (clipCmd) {
          // 不从 fzf execute 继承 stdout，避免无 TTY 时 kqueue EINVAL
          const proc = Bun.spawn(clipCmd, { stdin: 'pipe', stdout: 'ignore', stderr: 'ignore' })
          proc.stdin.write(firstId)
          proc.stdin.end()
          await proc.exited
        }
        // 从 fzf execute 运行时 stdout 可能不可用，用 stderr 输出
        const out = process.stderr?.writable ? process.stderr : process.stdout
        if (out?.write) out.write(`Copied: ${firstId}\n`)
        process.exit(0)
      }
      break
    case 'stop':
      if (cids.length > 0) {
        await runDocker(['stop', ...cids])
        process.exit(0)
      }
      break
    case 'run':
      if (cids.length > 0) {
        await runDocker(['start', ...cids])
        process.exit(0)
      }
      break
    case 'restart':
      if (cids.length > 0) {
        await runDocker(['restart', ...cids])
        process.exit(0)
      }
      break
    case 'delete':
      if (cids.length > 0) {
        await runDocker(['stop', ...cids])
        await runDocker(['rm', ...cids])
        process.exit(0)
      }
      break
    case 'image':
      if (cids.length > 0 && iids.length === 0) {
        process.stderr.write('i (rmi) only works on images, select from the === IMAGES === section.\n')
        process.exit(1)
      }
      if (iids.length > 0) {
        await runDocker(['rmi', ...iids])
        process.exit(0)
      }
      break
    default:
      process.stderr.write(`Unknown action: ${action}\n`)
      process.exit(1)
  }
  process.exit(0)
}

// --- dinfo: Docker Hub v2 API ---

async function fetchJson(url: string): Promise<unknown> {
  const res = await fetch(url)
  if (!res.ok)
    throw new Error(`HTTP ${res.status}`)
  return res.json() as Promise<unknown>
}

async function dinfo(repoArg: string, tag: string, arch: string, os: string) {
  let repo = repoArg
  let repoJson: unknown

  const tryRepo = async (r: string) => fetchJson(`https://hub.docker.com/v2/repositories/${r}`)

  process.stdout.write(`== repo: ${repo} ==\n`)
  try {
    repoJson = await tryRepo(repo)
  }
  catch {
    if (!repoArg.includes('/')) {
      repo = `library/${repoArg}`
      process.stdout.write(`repo ${repoArg} not found, trying official: ${repo}\n`)
      try {
        repoJson = await tryRepo(repo)
      }
      catch {
        process.stdout.write(`failed to fetch repo: ${repoArg} (also tried ${repo})\n`)
        process.exit(1)
      }
    }
    else {
      process.stdout.write(`failed to fetch repo: ${repo}\n`)
      process.exit(1)
    }
  }

  process.stdout.write(JSON.stringify(repoJson, null, 2) + '\n\n')

  process.stdout.write(`== tag: ${repo}:${tag} ==\n`)
  let tagJson: unknown
  try {
    tagJson = await fetchJson(`https://hub.docker.com/v2/repositories/${repo}/tags/${tag}`)
  }
  catch {
    process.stdout.write(`failed to fetch tag: ${repo}:${tag}\n`)
    process.exit(1)
  }
  process.stdout.write(JSON.stringify(tagJson, null, 2) + '\n\n')

  const tagObj = tagJson as { images?: Array<{ architecture: string; os: string; digest: string; size: number }> }
  const images = tagObj?.images ?? []
  const matched = images.filter((img: { architecture: string; os: string }) => img.architecture === arch && img.os === os)

  process.stdout.write(`== images (os=${os}, arch=${arch}) ==\n`)
  if (matched.length === 0) {
    process.stdout.write(`no images found: ${repo}:${tag} (os=${os}, arch=${arch})\n`)
    process.exit(1)
  }
  for (const img of matched)
    process.stdout.write(`${img.digest}  ${(img.size / 1024 / 1024).toFixed(2)} MiB\n`)
  process.exit(0)
}

async function main() {
  const [, , sub, ...rest] = process.argv

  if (!sub || sub === '-h' || sub === '--help') {
    process.stderr.write(
      'Usage:\n' +
      '  docker.ts dinfo <repo> <tag> [arch] [os]\n' +
      '  docker.ts list\n' +
      '  docker.ts list containers [--all]\n' +
      '  docker.ts dispatch <action> [line...]\n',
    )
    process.exit(sub ? 0 : 1)
  }

  if (sub === 'dispatch') {
    const [action, ...lines] = rest
    if (!action) {
      process.stderr.write('Usage: docker.ts dispatch <action> [line...]\n')
      process.exit(1)
    }
    await dispatch(action, lines)
    return
  }

  if (sub === 'list') {
    if (rest[0] === 'containers') {
      await listContainers(rest.includes('--all'))
      return
    }
    if (!rest.length) {
      await listDd()
      return
    }
  }

  if (sub === 'dinfo') {
    const [repo, tag, arch = 'amd64', os = 'linux'] = rest
    if (!repo || !tag) {
      process.stderr.write('Usage: dinfo <repo> <tag> [arch] [os]\n')
      process.stderr.write('Example: dinfo clickhouse/clickhouse-server 26.1.2 arm64 linux\n')
      process.exit(1)
    }
    await dinfo(repo, tag, arch, os)
    return
  }

  process.stderr.write('Unknown subcommand: ' + sub + '\n')
  process.exit(1)
}

main()
