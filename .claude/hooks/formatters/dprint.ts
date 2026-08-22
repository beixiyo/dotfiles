import path from 'node:path'

import { findExecutable } from '../lib/executables'
import { runProcess } from '../lib/process'

const DPRINT_EXTENSIONS = new Set([
  '.css',
  '.less',
  '.scss',
  '.html',

  '.js',
  '.jsx',
  '.ts',
  '.tsx',
  '.vue',

  '.lua',
  '.md',
  '.mdx',

  '.json',
  '.yaml',
  '.yml',
])

/**
 * 使用用户的全局 dprint 配置完成最终格式化
 */
export function runDprint(filePath: string, cwd: string): boolean {
  if (!DPRINT_EXTENSIONS.has(path.extname(filePath).toLowerCase())) return false

  const dprint = findExecutable(path.dirname(filePath), 'dprint')
  if (!dprint) return false

  runProcess(
    dprint,
    ['fmt', '--config-discovery=global', '--allow-no-files', filePath],
    { cwd },
  )

  return true
}
