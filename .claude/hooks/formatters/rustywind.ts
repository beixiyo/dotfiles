import path from 'node:path'

import { findExecutable } from '../lib/executables'
import { runProcess } from '../lib/process'

const RUSTYWIND_EXTENSIONS = new Set([
  '.html',

  '.js',
  '.jsx',
  '.ts',
  '.tsx',

  '.vue',
  '.svelte',
  '.astro',
])

export function runRustywind(filePath: string, cwd: string): boolean {
  if (!RUSTYWIND_EXTENSIONS.has(path.extname(filePath).toLowerCase())) return false

  const rustywind = findExecutable(path.dirname(filePath), 'rustywind')
  if (!rustywind) return false

  runProcess(rustywind, ['--write', filePath], { cwd })

  return true
}
