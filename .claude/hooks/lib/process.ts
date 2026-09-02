import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

type ProcessOutput = 'ignore' | 'inherit'

type RunProcessOptions = {
  cwd?: string
  timeout?: number
  /** 追加到当前进程环境之上的变量 */
  env?: Record<string, string>
  stdout?: ProcessOutput
  stderr?: ProcessOutput
}

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
    timeout: options.timeout,
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
