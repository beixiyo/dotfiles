import path from 'node:path'

import { findExecutable } from '../lib/executables'
import { runProcess } from '../lib/process'

const OXFMT_EXTENSIONS = new Set(['.jsx', '.tsx'])

/**
 * 使用 Oxfmt 的 Tailwind 排序能力处理 JSX / TSX
 */
export function runOxfmt(filePath: string, cwd: string): boolean {
  if (!OXFMT_EXTENSIONS.has(path.extname(filePath).toLowerCase())) return false

  const oxfmt = findExecutable(path.dirname(filePath), 'oxfmt')
  if (!oxfmt) return false

  runProcess(oxfmt, ['--write', filePath], { cwd })

  return true
}
