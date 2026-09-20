/**
 * 子进程工具（扩展共享）
 *
 * 统一 detached bash 封装：子进程自成进程组（pgid = pid），
 * 超时可整组击杀 bash→bun→nvim 链，不留孤儿
 */
import type { ChildProcess } from 'node:child_process'
import { spawn } from 'node:child_process'

export interface DetachedResult {
  code: number | null
  stdout: string
}

/** 负 pid 击杀整组进程，组不存在时退回单进程击杀 */
export function killProcessGroup(child: ChildProcess): void {
  try {
    if (child.pid) process.kill(-child.pid, 'SIGKILL')
    else child.kill('SIGKILL')
  }
  catch {
    child.kill('SIGKILL')
  }
}

/** detached 跑 `bash -c <cmd>`：stdin 灌入、stdout 收集、可选超时整组击杀
 * spawn 失败（如 bash 不存在）resolve null；被超时击杀时 code 为 null，
 * stdout 为已收到的部分输出 */
export function runDetached(cmd: string, opts: { input?: string; waitMs?: number } = {}): Promise<DetachedResult | null> {
  return new Promise((resolve) => {
    const child = spawn('bash', ['-c', cmd], { stdio: ['pipe', 'pipe', 'ignore'], detached: true })
    let out = ''
    const timer = opts.waitMs
      ? setTimeout(() => killProcessGroup(child), opts.waitMs)
      : undefined

    child.stdout.on('data', (chunk) => {
      out += chunk
    })
    child.on('error', () => {
      if (timer) clearTimeout(timer)
      resolve(null)
    })
    child.on('close', (code) => {
      if (timer) clearTimeout(timer)
      resolve({ code, stdout: out })
    })

    if (opts.input !== undefined) child.stdin.write(opts.input)
    child.stdin.end()
  })
}

/** 射后不理：通知类副作用不阻塞调用方（进程 unref，父进程可先行退出） */
export function fireAndForget(cmd: string): void {
  spawn('bash', ['-c', cmd], { stdio: 'ignore', detached: true }).unref()
}
