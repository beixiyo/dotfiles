import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

type ProcessOutput = 'ignore' | 'inherit'

type RunProcessOptions = {
  cwd?: string
  /** 子进程硬超时（毫秒）；默认 30s，超时 SIGTERM 子进程，防止 headless nvim 等外部进程挂死整个 hook */
  timeout?: number
  /** 追加到当前进程环境之上的变量 */
  env?: Record<string, string>
  stdout?: ProcessOutput
  stderr?: ProcessOutput
}

const DEFAULT_PROCESS_TIMEOUT_MS = 30_000

export function readStdin(): string {
  return readFileSync(0, 'utf8')
}

export function runProcess(
  command: string,
  args: string[],
  options: RunProcessOptions = {},
): void {
  spawnSync(command, args, {
    cwd: options.cwd,
    timeout: options.timeout ?? DEFAULT_PROCESS_TIMEOUT_MS,
    env: options.env ? { ...process.env, ...options.env } : undefined,
    windowsHide: true,
    shell: process.platform === 'win32' && /\.(?:bat|cmd)$/i.test(command),
    stdio: [
      'ignore',
      options.stdout ?? 'ignore',
      options.stderr ?? 'inherit',
    ],
  })
}
