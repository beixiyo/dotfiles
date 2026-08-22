import path from 'node:path'

import { findExecutable } from '../lib/executables'
import { runProcess } from '../lib/process'
import { isLintableFile } from './file-types'

/**
 * 使用 Oxlint 的自动修复能力处理 JavaScript / TypeScript 文件
 */
export function runOxlint(filePath: string, cwd: string): boolean {
  if (!isLintableFile(filePath)) return false

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
