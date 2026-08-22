import path from 'node:path'

import { findExecutable } from '../lib/executables'
import { runProcess } from '../lib/process'
import { isLintableFile } from './file-types'

/**
 * 当 Oxlint 不可用时，使用项目中的 ESLint 兼容旧项目配置
 */
export function runEslint(filePath: string, cwd: string): boolean {
  if (!isLintableFile(filePath)) return false

  const eslint = findExecutable(path.dirname(filePath), 'eslint')
  if (!eslint) return false

  runProcess(eslint, [
    '--fix',
    '--fix-type',
    'layout,suggestion,directive',

    '--rule',
    'unused-imports/no-unused-imports: off',

    '--rule',
    'unused-imports/no-unused-vars: off',

    '--rule',
    'prefer-const: off',
    filePath,
  ], { cwd })

  return true
}
