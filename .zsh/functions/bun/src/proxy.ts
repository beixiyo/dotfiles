#!/usr/bin/env bun

import { parseArgs } from 'node:util'

/**
 * Proxy helper for zsh:
 *
 * - setProxy: 生成 export + git config 的 shell 片段
 * - unsetProxy: 生成 unset + git config 清理的 shell 片段
 *
 * 设计用法（在 zsh 里）：
 *
 *   # 设置代理（保持现有命令名）
 *   setProxy() {
 *     eval "$(~/.zsh/functions/bun/proxy.ts set "$@")"
 *   }
 *
 *   unsetProxy() {
 *     eval "$(~/.zsh/functions/bun/proxy.ts unset "$@")"
 *   }
 *
 * 注意：本脚本不会直接修改当前 shell 环境，而是输出 shell 语句。
 */

type ProxyCommand = 'set' | 'unset'

interface SetProxyOptions {
  url: string
  port: number
  noProxy: string
  scheme: string
}

const PROXY_ENV_VARS = [
  'http_proxy',
  'HTTP_PROXY',
  'https_proxy',
  'HTTPS_PROXY',
  'all_proxy',
  'ALL_PROXY',
] as const

const NO_PROXY_ENV_VARS = [
  'no_proxy',
  'NO_PROXY',
] as const

const ALL_PROXY_ENV_VARS: readonly string[] = [
  ...PROXY_ENV_VARS,
  ...NO_PROXY_ENV_VARS,
]

const PROXY_GIT_CONFIG_KEYS = [
  'http.proxy',
  'https.proxy',
] as const

function isPort(value: string): boolean {
  return /^[0-9]+$/.test(value)
}

function isUrl(value: string): boolean {
  return value.includes('://')
}

function parseSetArgs(args: string[]): SetProxyOptions {
  const {
    values,
    positionals,
  } = parseArgs({
    args,
    options: {
      'port': {
        type: 'string',
        short: 'p',
      },
      'scheme': {
        type: 'string',
        short: 's',
      },
      'url': {
        type: 'string',
        short: 'u',
      },
      'no-proxy': {
        type: 'string',
        short: 'n',
      },
    },
    allowPositionals: true,
  })

  const scheme
    = typeof values.scheme === 'string' && values.scheme.length > 0
      ? values.scheme
      : 'http'

  let url
    = typeof values.url === 'string' && values.url.length > 0
      ? values.url
      : `${scheme}://127.0.0.1`

  let port: number
  if (typeof values.port === 'string') {
    if (!isPort(values.port)) {
      throw new Error(`端口参数错误: ${values.port}`)
    }
    port = Number(values.port)
  }
  else {
    port = 7890
  }

  const noProxy
    = typeof values['no-proxy'] === 'string' && values['no-proxy'].length > 0
      ? values['no-proxy']
      : 'localhost,127.0.0.1,::1,192.168.0.0/16,10.0.0.0/8'

  for (const arg of positionals) {
    if (isPort(arg)) {
      port = Number(arg)
    }
    else if (isUrl(arg)) {
      url = arg
    }
    else {
      throw new Error(
        `未知参数: ${arg}\n`
        + '用法: setProxy [URL] [端口] | setProxy [-p|--port <端口>] [-u|--url <URL>] [-s|--scheme <协议>] [-n|--no-proxy <排除列表>]\n'
        + '示例: setProxy 8080 | setProxy -p 8080 | setProxy --url http://proxy.example.com | setProxy -s socks5 -p 7890',
      )
    }
  }

  return { url, port, noProxy, scheme }
}

function buildSetProxyShell(opts: SetProxyOptions): string {
  const proxy = `${opts.url}:${opts.port}`
  const noProxy = opts.noProxy

  const lines = [
    `echo "🔧 设置代理: ${proxy}"`,
    `echo "🚫 排除地址: ${noProxy}"`,
    ...PROXY_ENV_VARS.map(name => `export ${name}=${proxy}`),
    ...NO_PROXY_ENV_VARS.map(name => `export ${name}=${noProxy}`),

    ...PROXY_GIT_CONFIG_KEYS.map(key => `git config --global ${key} "${proxy}"`),

    `echo`,
    `echo "🔑 已设置环境变量:"`,
    ...PROXY_ENV_VARS.map(name => `echo "  ${name.padEnd(12, ' ')}${proxy}"`),
    ...NO_PROXY_ENV_VARS.map(name => `echo "  ${name.padEnd(12, ' ')}${noProxy}"`),
    `echo`,

    `echo "🔑 已设置 git config:"`,
    ...PROXY_GIT_CONFIG_KEYS.map(key => `echo "  ${key}=${proxy}"`),
  ]

  return `${lines.join('\n')}\n`
}

function buildUnsetProxyShell(): string {
  const lines = [
    `echo "🔧 清除代理..."`,
    `unset ${ALL_PROXY_ENV_VARS.join(' ')}`,
    ...PROXY_GIT_CONFIG_KEYS.map(
      key => `git config --global --unset ${key} 2>/dev/null || true`,
    ),

    `echo`,
    `echo "🔑 已清除环境变量:"`,
    ...ALL_PROXY_ENV_VARS.map(name => `echo "  ${name}"`),
    `echo`,

    `echo "🔑 已删除 git config:"`,
    ...PROXY_GIT_CONFIG_KEYS.map(key => `echo "  ${key}"`),
  ]
  return `${lines.join('\n')}\n`
}

function printUsage(): void {
  console.error(
    [
      '用法:',
      '  proxy.ts set   [options]  # 生成设置代理的 shell 片段',
      '  proxy.ts unset           # 生成清除代理的 shell 片段',
      '',
      '示例（在 zsh 中包一层函数）:',
      '  setProxy() { eval "$(~/.zsh/functions/bun/proxy.ts set "$@")" }',
      '  unsetProxy() { eval "$(~/.zsh/functions/bun/proxy.ts unset "$@")" }',
    ].join('\n'),
  )
}

async function main() {
  const [, , sub, ...rest] = process.argv

  if (!sub || sub === '-h' || sub === '--help') {
    printUsage()
    process.exit(sub
      ? 0
      : 1)
  }

  if (sub !== 'set' && sub !== 'unset') {
    console.error(`未知子命令: ${sub}`)
    printUsage()
    process.exit(1)
  }

  try {
    if (sub === 'set') {
      const opts = parseSetArgs(rest)
      process.stdout.write(buildSetProxyShell(opts))
    }
    else if (sub === 'unset') {
      process.stdout.write(buildUnsetProxyShell())
    }
    process.exit(0)
  }
  catch (err) {
    console.error((err as Error).message)
    process.exit(1)
  }
}

main()
