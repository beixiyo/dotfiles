#!/usr/bin/env bun

import { readlinkSync, unlinkSync } from 'fs'
import { assertCmd, detectClipCopy, fzf, spawnFzfCapture } from './fzf-shared'

const PROCESS_BUN = `${import.meta.dir}/process.ts`

function midTrunc(s: string, max: number): string {
  if (s.length <= max) return s
  const h = Math.max(Math.floor(max / 2) - 1, 1)
  let t = max - h - 3
  if (t < 1) t = 1
  if (h + 3 + t > max) t = max - h - 3
  return s.slice(0, h) + '...' + s.slice(-t)
}

type PortMap = Record<string, string>

function parseLsofPorts(lsofOutput: string): PortMap {
  const map: PortMap = {}
  const dup = new Set<string>()

  for (const line of lsofOutput.split('\n')) {
    const fields = line.trim().split(/\s+/)
    if (fields.length < 2 || fields[0] === 'COMMAND') continue

    const pid = fields[1]
    const name = fields[fields.length - 2]?.replace(/ \(LISTEN\)$/, '') ?? ''
    const portMatch = name.match(/:(\d+)$/)
    if (!portMatch) continue

    const port = portMatch[1]
    const key = `${pid}\x00${port}`
    if (dup.has(key)) continue
    dup.add(key)

    map[pid] = map[pid]
      ? map[pid] + ',' + port
      : port
  }
  return map
}


function extractAppName(pid: string, args: string): string {
  const appMatch = args.match(/\/([^/]+)\.app\//)
  if (appMatch) return appMatch[1]

  const first = args.split(/\s+/)[0]

  // Chromium/Electron 子进程通过 /proc/self/exe 或 /proc/<N>/exe 启动自身，
  // 需解析符号链接拿到真实可执行路径，否则全部归到 "exe" 伪分组
  if (/^\/proc\/(self|\d+)\/exe/.test(first)) {
    try {
      const real = readlinkSync(`/proc/${pid}/exe`)
      const slash = real.lastIndexOf('/')
      return slash >= 0 ? real.slice(slash + 1) : real
    } catch {
      // 进程已退出或无权限，回退到默认逻辑
    }
  }

  const slash = first.lastIndexOf('/')
  return slash >= 0 ? first.slice(slash + 1) : first
}

interface ProcInfo {
  pid: string
  mem: number
  port: string
  args: string
}

interface ProcGroup {
  name: string
  procs: ProcInfo[]
  totalMem: number
  allPorts: string
  allPids: string[]
}

function buildGroups(
  psOutput: string,
  portMap: PortMap,
): ProcGroup[] {
  const procs: ProcInfo[] = []
  for (const line of psOutput.split('\n')) {
    const trimmed = line.trim()
    if (!trimmed || trimmed.startsWith('PID')) continue
    const match = trimmed.match(/^(\d+)\s+(\d+)\s+(.+)$/)
    if (!match) continue
    const [, pid, rss, args] = match
    procs.push({
      pid,
      mem: parseInt(rss, 10) / 1024,
      port: portMap[pid] ?? '-',
      args,
    })
  }

  const groupMap = new Map<string, ProcInfo[]>()
  for (const p of procs) {
    const key = extractAppName(p.pid, p.args)
    if (!groupMap.has(key)) groupMap.set(key, [])
    groupMap.get(key)!.push(p)
  }

  const groups: ProcGroup[] = []
  for (const [name, gProcs] of groupMap) {
    gProcs.sort((a, b) => b.mem - a.mem)
    const totalMem = gProcs.reduce((s, p) => s + p.mem, 0)
    const ports = [...new Set(gProcs.map(p => p.port).filter(p => p !== '-'))]
    groups.push({
      name,
      procs: gProcs,
      totalMem,
      allPorts: ports.join(',') || '-',
      allPids: gProcs.map(p => p.pid),
    })
  }

  groups.sort((a, b) => b.totalMem - a.totalMem)
  return groups
}

function formatCollapsed(groups: ProcGroup[], cmdMax: number): string {
  const lines: string[] = []
  for (const g of groups) {
    if (g.procs.length === 1) {
      const p = g.procs[0]
      lines.push(`${p.pid}\t${p.mem.toFixed(1)}\t${p.port}\t${midTrunc(p.args, cmdMax)}\t${p.args}`)
    } else {
      lines.push(
        `▶ [${g.procs.length}]\t${g.totalMem.toFixed(1)}\t${g.allPorts}\t${g.name}\tGRP:${g.allPids.join(',')}`
      )
    }
  }
  return lines.join('\n')
}

function formatExpanded(groups: ProcGroup[], cmdMax: number): string {
  const lines: string[] = []
  for (const g of groups) {
    if (g.procs.length === 1) {
      const p = g.procs[0]
      lines.push(`${p.pid}\t${p.mem.toFixed(1)}\t${p.port}\t${midTrunc(p.args, cmdMax)}\t${p.args}`)
      continue
    }

    lines.push(
      `▶ [${g.procs.length}]\t${g.totalMem.toFixed(1)}\t${g.allPorts}\t${g.name}\tGRP:${g.allPids.join(',')}`
    )
    for (let i = 0; i < g.procs.length; i++) {
      const p = g.procs[i]
      const branch = i < g.procs.length - 1 ? '├ ' : '└ '
      lines.push(
        `  ${p.pid}\t${p.mem.toFixed(1)}\t${p.port}\t  ${branch}${midTrunc(p.args, cmdMax - 4)}\t${p.args}`
      )
    }
  }
  return lines.join('\n')
}

function extractKillPids(selected: string): string[] {
  const pids = new Set<string>()
  for (const line of selected.split('\n')) {
    if (!line) continue
    const cols = line.split('\t')
    const hidden = cols[4] ?? ''
    if (hidden.startsWith('GRP:')) {
      for (const pid of hidden.slice(4).split(',')) {
        if (/^\d+$/.test(pid)) pids.add(pid)
      }
    } else {
      const pid = cols[0]?.trim()
      if (pid && /^\d+$/.test(pid)) pids.add(pid)
    }
  }
  return [...pids]
}

async function main(): Promise<void> {
  assertCmd('fzf')

  const cmdMax = Math.max(parseInt(process.env.FP_CMD_MAX ?? '70', 10), 20)
  const clipCmd = detectClipCopy()
  const portGuide = `Multi ⇥ │ Copy ${fzf.optHint}C │ Kill ↵`
  const collapsedGuide = `Multi ⇥ │ Expand ^E │ Copy ${fzf.optHint}C │ Kill ↵`
  const expandedGuide = `Multi ⇥ │ Collapse ^E │ Copy ${fzf.optHint}C │ Kill ↵`

  const clipBind = clipCmd !== 'cat'
    ? [`--bind`, `alt-c:execute-silent(printf '%s\\t%s\\t%s\\t%s\\n' {1} {2} {3} {5} | ${clipCmd})+abort`]
    : []

  const fzfBaseOpts = ['--delimiter', '\t', '--with-nth', '1,2,3,4']

  const lsofResult = Bun.spawnSync(
    ['lsof', '-iTCP', '-sTCP:LISTEN', '-P', '-n'],
    { stdout: 'pipe', stderr: 'pipe' },
  )
  const lsofOutput = lsofResult.stdout.toString()
  const portMap = parseLsofPorts(lsofOutput)

  const argv = process.argv.slice(2)

  if (argv.length === 1 && /^\d+$/.test(argv[0])) {
    const port = argv[0]

    if (!Bun.which('lsof')) {
      console.error('lsof is required but not installed')
      process.exit(1)
    }

    const lsofPort = Bun.spawnSync(
      ['lsof', '-ti', `:${port}`],
      { stdout: 'pipe', stderr: 'pipe' },
    )
    const pidList = lsofPort.stdout.toString().trim()
    if (!pidList) {
      console.log(`no process found listening on port ${port}`)
      return
    }

    const pids = pidList.split('\n').filter(Boolean)
    const rows: string[] = []

    for (const pid of pids) {
      const rssResult = Bun.spawnSync(['ps', '-p', pid, '-o', 'rss='], { stdout: 'pipe', stderr: 'pipe' })
      const argsResult = Bun.spawnSync(['ps', '-p', pid, '-o', 'args='], { stdout: 'pipe', stderr: 'pipe' })

      const rss = rssResult.stdout.toString().trim()
      const args = argsResult.stdout.toString().trim().replace(/^[\s\t]+/, '')
      const mem = (parseInt(rss || '0', 10) / 1024).toFixed(1)
      const pc = portMap[pid] ?? port
      const argsShow = midTrunc(args, cmdMax)

      rows.push(`${pid}\t${mem}\t${pc}\t${argsShow}\t${args}`)
    }

    const input = `PID\tMEM(MB)\tPORT\tCOMMAND\n${rows.join('\n')}`

    const [, selected] = await spawnFzfCapture([
      '-m',
      ...fzfBaseOpts,
      '--bind', fzf.tabToggleDown,
      ...clipBind,
      '--header', `Port ${port} │ ${portGuide}`,
      '--header-lines', '1',
      '--reverse',
    ], input)

    if (!selected) return

    const killPids = selected.split('\n')
      .map(l => l.split('\t')[0])
      .filter(p => /^\d+$/.test(p))

    if (killPids.length > 0) {
      Bun.spawnSync(['bun', 'run', PROCESS_BUN, 'kill', ...killPids], {
        stdin: 'inherit',
        stdout: 'inherit',
        stderr: 'inherit',
      })
    }
  } else if (argv[0] === '--render') {
    const mode = argv[1] ?? 'collapsed'
    const statusLine = mode === 'expanded'
      ? expandedGuide
      : collapsedGuide
    const psResult = Bun.spawnSync(
      ['ps', 'axo', 'pid,rss,args'],
      { stdout: 'pipe', stderr: 'pipe' },
    )
    const groups = buildGroups(psResult.stdout.toString(), portMap)
    const list = mode === 'expanded'
      ? formatExpanded(groups, cmdMax)
      : formatCollapsed(groups, cmdMax)
    process.stdout.write(`${statusLine}\nPID\tMEM(MB)\tPORT\tCOMMAND\n${list}`)

  } else {
    const psResult = Bun.spawnSync(
      ['ps', 'axo', 'pid,rss,args'],
      { stdout: 'pipe', stderr: 'pipe' },
    )
    const groups = buildGroups(psResult.stdout.toString(), portMap)
    const list = formatCollapsed(groups, cmdMax)
    const input = `${collapsedGuide}\nPID\tMEM(MB)\tPORT\tCOMMAND\n${list}`

    const self = `bun run ${import.meta.path}`
    const stateFile = `/tmp/.fp-${process.pid}`
    // toggle bind 只输出 reload(...)，无需 change-header — 状态行作为 --header-lines 2 的第一行随内容刷新
    const toggleBind = `ctrl-e:transform(if [ -f ${stateFile} ]; then rm -f ${stateFile}; echo 'reload(${self} --render collapsed)'; else touch ${stateFile}; echo 'reload(${self} --render expanded)'; fi)`

    const [, selected] = await spawnFzfCapture([
      '-m',
      ...fzfBaseOpts,
      '--bind', fzf.tabToggleDown,
      '--bind', toggleBind,
      ...clipBind,
      '--header-lines', '2',
      '--reverse',
    ], input)

    try { unlinkSync(stateFile) } catch {}

    if (!selected) return

    const killPids = extractKillPids(selected)

    if (killPids.length > 0) {
      Bun.spawnSync(['bun', 'run', PROCESS_BUN, 'kill', ...killPids], {
        stdin: 'inherit',
        stdout: 'inherit',
        stderr: 'inherit',
      })
    }
  }
}

main().catch(() => process.exit(1))
