#!/usr/bin/env node
/**
 * 调试日志采集服务器
 *
 * 轻量 HTTP 服务器，接收 POST 日志条目，追加写入工作区的 debug.log 文件
 *
 * 特性：
 *   - 端口冲突自动处理（复用健康实例 / 杀残留旧进程 / 让位他程序）
 *   - PID 文件按端口隔离（.debug-server.<port>.pid），跨端口不串台
 *   - 多会话并发安全：游标增量读、按 source 范围清空、引用计数关停
 *
 * 接口：
 *   POST   /log              追加单条日志（JSON: { level, source, data? }）
 *   POST   /log/batch        批量追加（JSON: Array<LogEntry>）
 *   GET    /offset           当前日志字节偏移（复现前记下，复现后增量读）
 *   GET    /logs             读取（query: since=<offset> 增量、source=<前缀> 过滤、json=1）
 *   DELETE /logs             范围清空（必须带 source=<前缀>；整清需显式 all=1）
 *   GET    /health           健康检查（pid / port / logFile / sessions）
 *   POST   /register         登记会话（JSON: { session }）
 *   POST   /shutdown         关停（JSON: { session?, force? }；仍有他会话且非 force 时拒绝退出）
 *
 * 环境变量：DEBUG_PORT（默认 9210）、DEBUG_LOG（默认 ./debug.log）
 *
 * 并发模型：同一个被调试 app 的上报端口通常写死，故多会话往往共享同一 server + debug.log。
 *   靠「每会话 source 加 SESSION/ 前缀」+「游标增量读」+「范围清空」+「引用计数关停」隔离，
 *   从根本上消除「一方清空抹掉另一方日志」「一方收尾拔掉共享 server」的数据竞争。
 */

import { createServer, request as httpRequest } from 'node:http'
import { appendFile, readFile, writeFile, unlink, stat } from 'node:fs/promises'
import { resolve } from 'node:path'

const PORT = Number(process.env.DEBUG_PORT) || 9210
const LOG_FILE = resolve(process.env.DEBUG_LOG || './debug.log')
/** PID 文件按端口隔离，避免不同端口的 server 共用一个 PID 文件互相杀错 */
const PID_FILE = resolve(`.debug-server.${PORT}.pid`)

const CORS = { 'Access-Control-Allow-Origin': '*' }

/** 活跃会话集合：用于引用计数关停 */
const sessions = new Set()

/** 发送 GET 请求并返回解析后的 JSON（失败 reject，error 透传 .code） */
function probe(path, timeout = 1500) {
  return new Promise((resolveProbe, reject) => {
    const req = httpRequest(
      { hostname: '127.0.0.1', port: PORT, path, method: 'GET', timeout },
      (res) => {
        const chunks = []
        res.on('data', c => chunks.push(c))
        res.on('end', () => {
          try { resolveProbe(JSON.parse(Buffer.concat(chunks).toString())) }
          catch { reject(new Error('bad json')) }
        })
      },
    )
    req.on('error', reject)
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout')) })
    req.end()
  })
}

/**
 * 探测端口上是否有健康实例。
 * ECONNREFUSED（没人监听）立即返回 null —— 不重试不等待，冷启动零额外延迟；
 * 仅 timeout / 坏响应（可能是健康实例瞬时卡顿）才重试几次。
 */
async function probeHealthWithRetry(attempts = 3) {
  for (let i = 0; i < attempts; i++) {
    try {
      const health = await probe('/health', 2000)
      if (health?.status === 'running')
        return health
    } catch (err) {
      if (err.code === 'ECONNREFUSED')
        return null
    }
    if (i < attempts - 1)
      await new Promise(r => setTimeout(r, 300))
  }
  return null
}

/** 读取 PID 文件，缺失 / 损坏返回 0 */
async function readPid() {
  try { return Number(await readFile(PID_FILE, 'utf-8')) || 0 }
  catch { return 0 }
}

/** 杀掉残留旧进程 */
async function killStalePid() {
  const pid = await readPid()
  if (pid > 0 && pid !== process.pid) {
    try { process.kill(pid, 'SIGTERM') } catch {}
    await new Promise(r => setTimeout(r, 500))
  }
}

/** 退出时清理本进程写的 PID 文件 */
async function cleanup() {
  if (await readPid() === process.pid)
    await unlink(PID_FILE).catch(() => {})
}

/** 启动前确保端口可用：健康实例 → 复用；残留进程 → 杀；他程序占用 → 让位 */
async function ensurePortAvailable() {
  const health = await probeHealthWithRetry()
  if (health) {
    console.log(`[debug-server] 已在端口 ${PORT} 运行，复用现有实例 (日志: ${health.logFile})`)
    process.exit(0)
  }

  await killStalePid()

  try {
    await probe('/health')
    console.error(`[debug-server] 端口 ${PORT} 被其他程序占用，请设置 DEBUG_PORT 使用其他端口`)
    process.exit(1)
  } catch {
    // 端口已释放，可以启动
  }
}

/** 格式化单条日志为文本行：[ISO] LEVEL [source] | data */
function formatEntry(entry) {
  const ts = new Date().toISOString()
  const level = (entry.level || 'INFO').toUpperCase().padEnd(5)
  const source = entry.source || 'unknown'
  const data = entry.data !== undefined
    ? ' | ' + (typeof entry.data === 'string' ? entry.data : JSON.stringify(entry.data))
    : ''
  return `[${ts}] ${level} [${source}]${data}\n`
}

/** 从日志行抽取 source */
function lineSource(line) {
  const m = line.match(/^\[[^\]]*\]\s+\S+\s+\[([^\]]*)\]/)
  return m ? m[1] : ''
}

/** 按 source 前缀筛选日志行：keep=true 留匹配的、false 留其余；返回规范化文本 */
function filterLines(content, prefix, keep) {
  const lines = content
    .split('\n')
    .filter(line => line && lineSource(line).startsWith(prefix) === keep)
  return lines.length ? lines.join('\n') + '\n' : ''
}

/** 解析请求体 JSON */
function parseBody(req) {
  return new Promise((resolveBody, reject) => {
    const chunks = []
    req.on('data', c => chunks.push(c))
    req.on('end', () => {
      try { resolveBody(JSON.parse(Buffer.concat(chunks).toString())) }
      catch { reject(new Error('Invalid JSON')) }
    })
    req.on('error', reject)
  })
}

function json(res, status, data) {
  res.writeHead(status, { 'Content-Type': 'application/json', ...CORS })
  res.end(JSON.stringify(data))
}

function text(res, status, body, extraHeaders = {}) {
  res.writeHead(status, { 'Content-Type': 'text/plain', ...CORS, ...extraHeaders })
  res.end(body)
}

// ── 主流程 ──────────────────────────────────────────────

await ensurePortAvailable()

const server = createServer(async (req, res) => {
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      ...CORS,
      'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    })
    return res.end()
  }

  try {
    const url = new URL(req.url, `http://localhost:${PORT}`)

    if (req.method === 'POST' && url.pathname === '/log') {
      await appendFile(LOG_FILE, formatEntry(await parseBody(req)))
      return json(res, 200, { ok: true })
    }

    if (req.method === 'POST' && url.pathname === '/log/batch') {
      const entries = await parseBody(req)
      if (!Array.isArray(entries)) return json(res, 400, { error: 'Expected array' })
      await appendFile(LOG_FILE, entries.map(formatEntry).join(''))
      return json(res, 200, { ok: true, count: entries.length })
    }

    if (req.method === 'GET' && url.pathname === '/offset') {
      let size = 0
      try { size = (await stat(LOG_FILE)).size } catch {}
      return json(res, 200, { offset: size })
    }

    // since=<offset> 增量、source=<前缀> 过滤、json=1
    if (req.method === 'GET' && url.pathname === '/logs') {
      const since = Number(url.searchParams.get('since')) || 0
      const sourcePrefix = url.searchParams.get('source') || ''
      const asJson = url.searchParams.get('json') === '1'
      let buf
      try { buf = await readFile(LOG_FILE) }
      catch { buf = Buffer.from('') }

      const nextOffset = buf.length
      // 文件被范围清空后体积可能变小，since 越界则从头读
      const sliceFrom = since > 0 && since <= buf.length ? since : 0
      let content = buf.slice(sliceFrom).toString('utf-8')
      if (sourcePrefix)
        content = filterLines(content, sourcePrefix, true)

      if (asJson)
        return json(res, 200, { offset: nextOffset, content })
      return text(res, 200, content || '(暂无日志)', { 'X-Log-Offset': String(nextOffset) })
    }

    // 范围清空（带 source=<前缀>）；整清需显式 all=1，杜绝误抹他人日志
    if (req.method === 'DELETE' && url.pathname === '/logs') {
      const sourcePrefix = url.searchParams.get('source') || ''
      if (sourcePrefix) {
        let content = ''
        try { content = await readFile(LOG_FILE, 'utf-8') } catch {}
        await writeFile(LOG_FILE, filterLines(content, sourcePrefix, false))
        return json(res, 200, { ok: true, scoped: sourcePrefix })
      }
      if (url.searchParams.get('all') === '1') {
        await writeFile(LOG_FILE, '')
        return json(res, 200, { ok: true, cleared: 'all' })
      }
      return json(res, 400, { error: '需带 ?source=<前缀> 范围清空；整清请显式 ?all=1' })
    }

    if (req.method === 'GET' && url.pathname === '/health') {
      return json(res, 200, { status: 'running', logFile: LOG_FILE, port: PORT, pid: process.pid, sessions: [...sessions] })
    }

    if (req.method === 'POST' && url.pathname === '/register') {
      const { session } = await parseBody(req).catch(() => ({}))
      if (session) sessions.add(String(session))
      return json(res, 200, { ok: true, sessions: [...sessions] })
    }

    // 关停；带 session 先减引用，仍有他会话且非 force 则拒绝退出
    if (req.method === 'POST' && url.pathname === '/shutdown') {
      const { session, force } = await parseBody(req).catch(() => ({}))
      if (session) sessions.delete(String(session))
      if (sessions.size > 0 && !force)
        return json(res, 409, { ok: false, message: 'other sessions active', remaining: [...sessions] })
      json(res, 200, { ok: true, message: 'shutting down' })
      await cleanup()
      return process.exit(0)
    }

    json(res, 404, { error: 'Not found' })
  } catch (err) {
    json(res, 500, { error: err.message })
  }
})

for (const sig of ['SIGTERM', 'SIGINT']) {
  process.on(sig, async () => {
    await cleanup()
    process.exit(0)
  })
}

// 端口被抢占（并发启动竞态）时安静让位，不崩溃
server.on('error', (err) => {
  if (err.code === 'EADDRINUSE') {
    console.log(`[debug-server] 端口 ${PORT} 已被占用，让位退出`)
    process.exit(0)
  }
  console.error(`[debug-server] 服务器错误: ${err.message}`)
  process.exit(1)
})

server.listen(PORT, async () => {
  await writeFile(PID_FILE, String(process.pid))
  console.log(`[debug-server] PID ${process.pid} 监听 http://localhost:${PORT}`)
  console.log(`[debug-server] 日志文件: ${LOG_FILE}`)
})
