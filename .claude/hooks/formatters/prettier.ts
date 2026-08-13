import path from 'node:path'

import { findExecutable } from '../lib/executables'
import { runProcess } from '../lib/process'

const PRETTIER_EXTENSIONS = new Set([
  '.css', '.html', '.js', '.jsx', '.json', '.less', '.md', '.mdx',
  '.scss', '.ts', '.tsx', '.vue', '.yaml', '.yml',
])

/**
 * dprint 不可用时，用 Prettier 作为开源项目的兼容兜底
 */
export function runPrettier(filePath: string, cwd: string): boolean {
  if (!PRETTIER_EXTENSIONS.has(path.extname(filePath).toLowerCase())) return false

  const prettier = findExecutable(path.dirname(filePath), 'prettier')
  if (!prettier) return false

  runProcess(prettier, ['--write', filePath], { cwd })

  return true
}
