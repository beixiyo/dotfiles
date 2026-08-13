import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'

type ProcessOutput = 'ignore' | 'inherit'

type RunProcessOptions = {
  cwd?: string
  timeout?: number
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
    windowsHide: true,
    shell: process.platform === 'win32' && /\.(?:bat|cmd)$/i.test(command),
    stdio: [
      'ignore',
      options.stdout ?? 'ignore',
      options.stderr ?? 'inherit',
    ],
  })
}
