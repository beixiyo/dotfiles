#!/usr/bin/env node
import { spawn } from 'node:child_process'
import { createServer } from 'node:http'
import { homedir } from 'node:os'
import { isAbsolute, join } from 'node:path'

const configuredPort = process.env.OPEN_NVIM_PORT
if (configuredPort !== undefined && (!/^\d+$/.test(configuredPort) || Number(configuredPort) < 1 || Number(configuredPort) > 65535)) {
  console.error('OPEN_NVIM_PORT must be an integer between 1 and 65535')
  process.exit(1)
}

let port = configuredPort === undefined ? 43123 : Number(configuredPort)
const lastPort = configuredPort === undefined ? 43132 : port
let lastRequest = 0

const server = createServer((req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*')
  res.setHeader('Cache-Control', 'no-store')

  const url = new URL(req.url || '/', `http://127.0.0.1:${port}`)
  if (req.method === 'GET' && url.pathname === '/open-nvim' && !url.search) {
    res.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' }).end('source-open-server-v1')
    return
  }

  if (req.method === 'OPTIONS' && url.pathname === '/open-nvim') {
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST')
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type')
    if (req.headers['access-control-request-private-network'] === 'true') res.setHeader('Access-Control-Allow-Private-Network', 'true')
    res.writeHead(204).end()
    return
  }

  if (
    url.pathname !== '/open-nvim' || !['GET', 'POST'].includes(req.method)
    || (req.method === 'POST' && req.headers['content-type'] !== 'application/json')
  ) {
    res.writeHead(403).end('Forbidden')
    return
  }

  if (Date.now() - lastRequest < 150) {
    res.writeHead(429).end('Too many requests')
    return
  }
  lastRequest = Date.now()

  const open = (value) => {
    if (!value || typeof value !== 'object') {
      res.writeHead(400).end('Invalid request')
      return
    }

    const file = value.file ?? value.path
    const number = (v, fallback) =>
      v === undefined || v === null
        ? fallback
        : typeof v === 'number'
        ? v
        : typeof v === 'string' && /^\d+$/.test(v)
        ? Number(v)
        : NaN

    const line = number(value.line, 1)
    const column = number(value.column, 1)

    if (
      typeof file !== 'string' || !isAbsolute(file) || file.includes('\0')
      || !Number.isSafeInteger(line) || line < 1 || line > 10000000
      || !Number.isSafeInteger(column) || column < 1 || column > 10000000
    ) {
      res.writeHead(400).end('Invalid file, line or column')
      return
    }
    const child = spawn(join(homedir(), '.local/bin/open-nvim'), [`${file}:${line}:${column}`], { env: { ...process.env, NVIM: '' } })
    let output = ''
    child.stdout.on('data', (chunk) => {
      output += chunk
    })
    child.stderr.on('data', (chunk) => {
      output += chunk
    })
    child.on('error', (error) => {
      if (!res.writableEnded) res.writeHead(500).end(error.message)
    })
    child.on('close', (code) => {
      if (!res.writableEnded) res.writeHead(code === 0 ? 200 : 500, { 'Content-Type': 'text/plain; charset=utf-8' }).end(output)
    })
  }

  if (req.method === 'GET') {
    open({ file: url.searchParams.get('file'), line: url.searchParams.get('line'), column: url.searchParams.get('column') })
    return
  }

  let body = ''
  req.setEncoding('utf8')

  req.on('data', (chunk) => {
    body += chunk
    if (body.length > 8192) req.destroy()
  })
  req.on('end', () => {
    try {
      open(JSON.parse(body))
    }
    catch {
      if (!res.writableEnded) res.writeHead(400).end('Invalid JSON')
    }
  })
})

server.on('error', (error) => {
  if (error.code === 'EADDRINUSE' && port < lastPort) {
    port++
    server.listen(port, '::')
    return
  }
  console.error(`open-nvim server: ${error.message}`)
  process.exitCode = 1
})
server.listen(port, '::', () => console.log(`open-nvim server: http://[::]:${port}/open-nvim`))
