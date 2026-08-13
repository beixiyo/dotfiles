import path from 'node:path'

import { findExecutable } from '../lib/executables'
import { runProcess } from '../lib/process'

const VV_MCP_REQUEST_TIMEOUT_MS = 2_800
const VV_MCP_PROCESS_TIMEOUT_MS = 3_000

/**
 * 通过当前 Neovim 实例连接的 LSP 执行修复
 */
export function runVvMcp(filePath: string, cwd: string): boolean {
  const vvMcp = findExecutable(path.dirname(filePath), 'vv-mcp')
  if (!vvMcp) return false

  runProcess(
    vvMcp,
    ['fix', '--timeout-ms', String(VV_MCP_REQUEST_TIMEOUT_MS), filePath],
    {
      cwd,
      timeout: VV_MCP_PROCESS_TIMEOUT_MS,
      stdout: 'ignore',
    },
  )

  return true
}
