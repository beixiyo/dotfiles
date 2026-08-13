import path from 'node:path'

import { findExecutable } from '../lib/executables'
import { runProcess } from '../lib/process'

const OXLINT_EXTENSIONS = new Set([
  '.cjs', '.cts', '.js', '.jsx', '.mjs', '.mts', '.ts', '.tsx',
])

/**
 * 使用 Oxlint 的自动修复能力处理 JavaScript / TypeScript 文件
 */
export function runOxlint(filePath: string, cwd: string): boolean {
  if (!OXLINT_EXTENSIONS.has(path.extname(filePath).toLowerCase())) return false

  const oxlint = findExecutable(path.dirname(filePath), 'oxlint')
  if (!oxlint) return false

  runProcess(oxlint, [
    '--fix',
    '--allow=unused-imports/no-unused-imports',
    '--allow=unused-imports/no-unused-vars',
    '--allow=prefer-const',
    filePath,
  ], { cwd })

  return true
}

/**
 * 判断文件是否属于 Oxlint / ESLint 的共同处理范围
 */
export function isLintableFile(filePath: string): boolean {
  return OXLINT_EXTENSIONS.has(path.extname(filePath).toLowerCase())
}
