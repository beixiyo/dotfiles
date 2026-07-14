#!/usr/bin/env bun

import { writeSync } from 'node:fs'

/**
 * Mihomo 代理节点管理：列出节点、查看当前节点、切换节点、延迟测试
 *
 * 子命令：
 *   mihomo.ts nodes            输出所有节点名（每行一个）
 *   mihomo.ts now              输出当前节点名
 *   mihomo.ts set <name>       切换到指定节点
 *   mihomo.ts test [name]      测试延迟；无参数测试整组，按延迟升序输出 `delay\tname`
 *   mihomo.ts test-stream      流式测试整组，完成即输出 `marker\tdelay\tname`（当前节点 ▶ + 绿色）
 *
 * 环境变量：
 *   MIHOMO_API           默认 http://127.0.0.1:9090
 *   MIHOMO_GROUP         默认 PROXY
 *   MIHOMO_SECRET        若配置了 secret，需设置此项
 *   MIHOMO_TIMEOUT_MS    普通请求超时，默认 3000
 *   MIHOMO_TEST_URL      延迟探测 URL，默认 gstatic generate_204
 *   MIHOMO_TEST_TIMEOUT  延迟探测超时 ms，默认 5000
 */

const API = process.env.MIHOMO_API ?? 'http://127.0.0.1:9090'
const GROUP = process.env.MIHOMO_GROUP ?? 'PROXY'
const SECRET = process.env.MIHOMO_SECRET ?? ''
const TIMEOUT_MS = Number(process.env.MIHOMO_TIMEOUT_MS ?? 3000)
const TEST_URL = process.env.MIHOMO_TEST_URL ?? 'http://www.gstatic.com/generate_204'
const TEST_TIMEOUT_MS = Number(process.env.MIHOMO_TEST_TIMEOUT ?? 5000)

/** 所有 mihomo 请求必须绕过代理（否则走自身会死锁）并带超时 */
async function api(
  path: string,
  init: RequestInit = {},
  timeoutMs = TIMEOUT_MS,
): Promise<Response | null> {
  const headers: Record<string, string> = { ...(init.headers as Record<string, string> | undefined) }
  if (SECRET) headers['Authorization'] = `Bearer ${SECRET}`
  return fetch(`${API}${path}`, {
    ...init,
    headers,
    signal: AbortSignal.timeout(timeoutMs),
    proxy: '',
  }).catch(() => null)
}

async function fetchGroup(): Promise<ProxyGroup> {
  const res = await api(`/proxies/${encodeURIComponent(GROUP)}`)
  if (!res || !res.ok) {
    console.error(`cannot connect to mihomo API (${API}) or group "${GROUP}" not found`)
    process.exit(1)
  }
  return (await res.json()) as ProxyGroup
}

async function setNode(name: string): Promise<void> {
  const res = await api(`/proxies/${encodeURIComponent(GROUP)}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name }),
  })
  if (!res || !res.ok) {
    const reason = res ? `HTTP ${res.status}: ${await res.text().catch(() => '')}` : 'network error'
    console.error(`switch failed (${reason})`)
    process.exit(1)
  }
  console.log(`switched to: ${name}`)
}

/** 测试单个节点延迟，返回毫秒数；超时/不可用返回 null */
async function testNode(name: string): Promise<number | null> {
  const q = `url=${encodeURIComponent(TEST_URL)}&timeout=${TEST_TIMEOUT_MS}`
  const res = await api(
    `/proxies/${encodeURIComponent(name)}/delay?${q}`,
    {},
    TEST_TIMEOUT_MS + 1000,
  )
  if (!res || !res.ok) return null
  const data = (await res.json().catch(() => null)) as { delay?: number } | null
  return typeof data?.delay === 'number' ? data.delay : null
}

/** 格式化延迟：数字右对齐 4 位，超时显示 ---- */
function fmtDelay(d: number | null): string {
  return d === null ? '----' : String(d).padStart(4)
}

/** 按延迟分档上色：<150 亮绿 / <300 绿 / <600 黄 / <1500 红 / 其余（超时）灰 */
function colorDelay(d: number | null): string {
  const text = fmtDelay(d)
  const code =
    d === null ? 90 :
    d < 150    ? 92 :
    d < 300    ? 32 :
    d < 600    ? 33 :
    d < 1500   ? 31 :
                 90
  return `\x1b[${code}m${text}\x1b[0m`
}

async function testAll(): Promise<void> {
  const g = await fetchGroup()
  const results = await Promise.all(
    g.all.map(async (name) => ({ name, delay: await testNode(name) })),
  )
  results.sort((a, b) => {
    if (a.delay === null && b.delay === null) return 0
    if (a.delay === null) return 1
    if (b.delay === null) return -1
    return a.delay - b.delay
  })
  for (const { name, delay } of results) console.log(`${fmtDelay(delay)}\t${name}`)
}

/** 流式测试：完成一个写一行，当前节点用 ▶ + 绿色高亮；供 fzf 实时消费 */
async function testStream(): Promise<void> {
  const g = await fetchGroup()
  const current = g.now
  await Promise.all(
    g.all.map(async (name) => {
      const d = await testNode(name)
      const marker = name === current ? '\x1b[1;32m▶\x1b[0m' : ' '
      writeSync(1, `${marker}\t${colorDelay(d)}\t${name}\n`)
    }),
  )
}

function usage(): never {
  console.error('用法: mihomo.ts <nodes|now|set <name>|test [name]>')
  process.exit(1)
}

async function main() {
  const [, , sub, ...rest] = process.argv
  if (!sub) usage()

  if (sub === 'nodes') {
    const g = await fetchGroup()
    console.log(g.all.join('\n'))
    return
  }
  if (sub === 'now') {
    const g = await fetchGroup()
    console.log(g.now)
    return
  }
  if (sub === 'set') {
    const name = rest[0]
    if (!name) usage()
    await setNode(name)
    return
  }
  if (sub === 'test') {
    const name = rest[0]
    if (name) {
      const d = await testNode(name)
      console.log(d === null ? 'timeout' : `${d}ms`)
      return
    }
    await testAll()
    return
  }
  if (sub === 'test-stream') {
    await testStream()
    process.exit(0)
  }
  usage()
}

main()

interface ProxyGroup {
  all: string[]
  now: string
}
