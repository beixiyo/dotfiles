#!/usr/bin/env node
/**
 * 本地调试日志采集服务器。多个会话共用一个文件，通过 source 前缀分别读取。
 *
 * 接口：
 *   POST /log、/log/batch   校验 source 后追加单条 / 批量日志
 *   GET  /offset           获取 { instance, offset }，作为下一轮采集起点
 *   GET  /logs             按会话前缀和实例游标读取，旧实例游标返回 409
 *   GET  /health           查询日志路径、实例身份及活跃会话
 *   POST /register         登记会话，重复登记幂等
 *   POST /shutdown         注销会话，最后一个会话退出时关闭服务器
 *   DELETE /logs           始终拒绝，避免破坏其他会话的字节游标
 *
 * 生命周期：
 *   取得端口 → 独占日志锁 → 归档上一轮 → 接收请求 → 停止接收 → 释放锁。
 *   复用实例不轮转；异常退出留下的锁不自动抢占。
 *
 * 环境变量：DEBUG_PORT 默认 9210，DEBUG_LOG 默认 ./debug.log（父目录须存在）。
 * 使用同步文件操作是针对低频本地调试的取舍，让追加、快照和轮转保持串行。
 */

import { createServer } from 'node:http'
import { randomUUID } from 'node:crypto'
import {
  appendFileSync,
  closeSync,
  existsSync,
  openSync,
  readFileSync,
  realpathSync,
  renameSync,
  unlinkSync,
  writeFileSync,
} from 'node:fs'
import { basename, dirname, join, resolve } from 'node:path'

// ── 配置与运行状态 ──────────────────────────────────────────

const PORT = Number(process.env.DEBUG_PORT) || 9210

// 统一符号链接路径，避免同一日志通过不同路径绕过独占锁。
const requestedLog = resolve(process.env.DEBUG_LOG || './debug.log')
const LOG_FILE = existsSync(requestedLog)
  ? realpathSync(requestedLog)
  : join(realpathSync(dirname(requestedLog)), basename(requestedLog))
const LOCK_FILE = LOG_FILE + '.lock'

const INSTANCE = randomUUID()
const SESSION_PATTERN = /^[a-zA-Z0-9_-]+$/
const SOURCE_PATTERN = /^[a-zA-Z0-9_-]+\/[a-zA-Z0-9_.:/-]+$/

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Expose-Headers': 'X-Log-Offset, X-Log-Instance',
}

/** 活跃会话控制关停；日志归属仍由每条记录的 source 明确指定 */
const sessions = new Set()

let ownsLock = false
let ready = false
let stopping = false

// ── 请求协议与日志格式 ──────────────────────────────────────

/** 客户端协议错误，和磁盘 / 服务错误区分 */
function badRequest(message) {
  return Object.assign(new Error(message), { status: 400 })
}

/** 每条日志保持单行，避免 data 中的换行伪造其他 source */
function formatEntry(entry) {
  if (!entry || typeof entry.source !== 'string' || !SOURCE_PATTERN.test(entry.source)) {
    throw badRequest('source 必须为 session/tag，例如 debug-a/request.start')
  }

  if (entry.level !== undefined && (typeof entry.level !== 'string' || !/^[a-zA-Z]+$/.test(entry.level))) {
    throw badRequest('level 必须为英文字母组成的日志级别')
  }

  const timestamp = new Date().toISOString()
  const level = (entry.level || 'INFO').toUpperCase().padEnd(5)
  const data = entry.data === undefined ? '' : ' | ' + JSON.stringify(entry.data)

  return `[${timestamp}] ${level} [${entry.source}]${data}\n`
}

/** 读取 JSON；无效请求返回 400，不影响已写入日志 */
async function readJsonBody(req) {
  const chunks = []
  for await (const chunk of req) {
    chunks.push(chunk)
  }

  try {
    return JSON.parse(Buffer.concat(chunks).toString())
  }
  catch {
    throw badRequest('请求体必须为有效 JSON')
  }
}

/** 登记和注销共用同一 session 命名规则 */
function validateSessionName(value) {
  if (typeof value !== 'string' || !SESSION_PATTERN.test(value)) {
    throw badRequest('session 必须为非空英文字母、数字、下划线或连字符')
  }

  return value
}

/** 所有 JSON 响应统一携带 CORS 和内容类型 */
function json(res, status, data) {
  res.writeHead(status, { ...CORS, 'Content-Type': 'application/json' })
  res.end(JSON.stringify(data))
}

// ── 资源释放 ────────────────────────────────────────────────

/** 只释放自己创建的锁；不自动抢锁或终止其他进程 */
function releaseLogLock() {
  if (ownsLock) {
    unlinkSync(LOCK_FILE)
    ownsLock = false
  }
}

/** 停止接收请求，让正在读取请求体的连接结束后再释放日志锁 */
function stopServer() {
  if (stopping) {
    return
  }

  stopping = true
  ready = false

  server.close(() => {
    releaseLogLock()
    process.exit(0)
  })
}

// ── 日志读写与会话操作 ──────────────────────────────────────

/** 全部验证并格式化后只追加一次，非法条目不会导致部分写入 */
function appendEntries(entries) {
  if (!Array.isArray(entries)) {
    throw badRequest('批量请求必须为日志数组')
  }

  const content = entries.map(formatEntry).join('')
  appendFileSync(LOG_FILE, content)
}

/** 注销调用方；有其他会话时只注销，不关闭共享服务器 */
function unregisterSession(session, res) {
  if (!sessions.has(session)) {
    throw badRequest('session 未登记，不能请求关停')
  }

  sessions.delete(session)

  if (sessions.size) {
    return json(res, 409, {
      ok: false,
      message: 'other sessions active',
      remaining: [...sessions],
    })
  }

  json(res, 200, { ok: true, message: 'shutting down' })
  stopServer()
}

/** 校验实例与字节边界，再从一致的文件快照中筛选本会话日志 */
function respondWithLogs(url, res) {
  const source = url.searchParams.get('source')
  if (!source || !/^[a-zA-Z0-9_-]+\/$/.test(source)) {
    throw badRequest('必须提供 source 会话前缀，例如 ?source=debug-a/')
  }

  const sinceValue = url.searchParams.get('since')
  const since = sinceValue === null ? 0 : Number(sinceValue)
  if (sinceValue !== null && (!/^\d+$/.test(sinceValue) || !Number.isSafeInteger(since))) {
    throw badRequest('since 必须为非负整数字节游标')
  }

  const instance = url.searchParams.get('instance')
  if (sinceValue !== null && !instance) {
    throw badRequest('增量读取必须同时提供 /offset 返回的 instance 和 since')
  }

  if (instance && instance !== INSTANCE) {
    return json(res, 409, {
      error: '服务器已重启，请重新登记并从新日志起点读取',
      code: 'INSTANCE_CHANGED',
      instance: INSTANCE,
    })
  }

  // 游标属于整个共享文件，过滤之后仍返回快照末尾的位置。
  const buf = readFileSync(LOG_FILE)
  if (since > buf.length || (since > 0 && buf[since - 1] !== 10)) {
    throw badRequest('游标越界或不在日志行边界，请使用服务器返回的 offset')
  }

  const content = buf
    .subarray(since)
    .toString()
    .split('\n')
    .filter(line => {
      const match = line.match(/^\[[^\]]+\]\s+\S+\s+\[([^\]]+)\]/)
      return match?.[1].startsWith(source)
    })
    .join('\n')

  if (url.searchParams.get('json') === '1') {
    return json(res, 200, {
      instance: INSTANCE,
      offset: buf.length,
      content: content ? content + '\n' : '',
    })
  }

  res.writeHead(200, {
    ...CORS,
    'Content-Type': 'text/plain',
    'X-Log-Offset': String(buf.length),
    'X-Log-Instance': INSTANCE,
  })
  return res.end(content || '(暂无日志)')
}

// ── HTTP 请求处理 ───────────────────────────────────────────

const server = createServer(async (req, res) => {
  if (!ready) {
    return json(res, 503, { error: '服务器正在启动或关闭，请稍后重试' })
  }

  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      ...CORS,
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    })
    return res.end()
  }

  try {
    const url = new URL(req.url, `http://127.0.0.1:${PORT}`)

    if (req.method === 'GET' && url.pathname === '/health') {
      return json(res, 200, {
        status: 'running',
        logFile: LOG_FILE,
        port: PORT,
        pid: process.pid,
        instance: INSTANCE,
        sessions: [...sessions],
      })
    }
    if (req.method === 'POST' && ['/log', '/log/batch', '/register', '/shutdown'].includes(url.pathname)) {
      const value = await readJsonBody(req)

      // 读取请求体会让出执行权，期间可能已由其他会话触发关停。
      if (!ready) {
        return json(res, 503, { error: '服务器正在关闭' })
      }

      if (url.pathname === '/log' || url.pathname === '/log/batch') {
        const entries = url.pathname === '/log' ? [value] : value
        appendEntries(entries)

        return json(res, 200, { ok: true, count: entries.length })
      }

      // 登记与注销只控制服务器生命周期，不隐式改变 source 过滤范围。
      const session = validateSessionName(value?.session)

      if (url.pathname === '/register') {
        sessions.add(session)

        return json(res, 200, {
          ok: true,
          instance: INSTANCE,
          sessions: [...sessions],
        })
      }

      return unregisterSession(session, res)
    }

    if (req.method === 'GET' && url.pathname === '/offset') {
      return json(res, 200, {
        instance: INSTANCE,
        offset: readFileSync(LOG_FILE).length,
      })
    }

    if (req.method === 'GET' && url.pathname === '/logs') {
      return respondWithLogs(url, res)
    }

    if (req.method === 'DELETE' && url.pathname === '/logs') {
      return json(res, 405, {
        error: '运行期间禁止删除日志；新一轮使用新游标，归档仅在新服务器启动时执行',
      })
    }

    json(res, 404, { error: 'Not found' })
  }
  catch (err) {
    json(res, err.status || 500, { error: err.message })
  }
})

// ── 启动与进程信号 ──────────────────────────────────────────

for (const signal of ['SIGTERM', 'SIGINT']) {
  process.on(signal, stopServer)
}

// 先取得端口，再锁定日志；失败实例从不轮转。就绪前所有请求返回 503。
server.on('error', async (err) => {
  if (err.code === 'EADDRINUSE') {
    try {
      const response = await fetch(`http://127.0.0.1:${PORT}/health`, {
        signal: AbortSignal.timeout(2000),
      })

      const health = await response.json()
      if (health.status === 'running' && health.logFile === LOG_FILE) {
        console.log(`[debug-server] 复用端口 ${PORT} 的实例 ${health.instance || '(旧版)'}`)
        process.exit(0)
      }
    }
    catch {
      // 探测失败不能认定为可复用实例，继续报告原始启动错误。
    }
  }

  console.error(`[debug-server] 启动失败：${err.message}；核对端口与日志路径后重试`)
  process.exit(1)
})

server.listen(PORT, '127.0.0.1', () => {
  try {
    const fd = openSync(LOCK_FILE, 'wx')
    ownsLock = true

    try {
      writeFileSync(fd, JSON.stringify({
        pid: process.pid,
        port: PORT,
        instance: INSTANCE,
      }))
    }
    finally {
      closeSync(fd)
    }

    // 固定保留上一轮，不引入历史目录、定时器或清理策略。
    if (existsSync(LOG_FILE)) {
      renameSync(LOG_FILE, LOG_FILE + '.previous')
    }

    writeFileSync(LOG_FILE, '')
    ready = true

    console.log(`[debug-server] http://127.0.0.1:${PORT} 日志: ${LOG_FILE} 实例: ${INSTANCE}`)
  }
  catch (err) {
    console.error(`[debug-server] 启动失败：${err.message}。若锁残留，确认其中 PID 已退出后手动移除 ${LOCK_FILE}；不会自动抢锁`)
    releaseLogLock()
    server.close(() => process.exit(1))
  }
})
