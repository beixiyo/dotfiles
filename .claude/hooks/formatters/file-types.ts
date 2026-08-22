import path from 'node:path'

const LINTABLE_EXTENSIONS = new Set([
  '.cjs',
  '.cts',
  '.js',
  '.jsx',
  '.mjs',
  '.mts',
  '.ts',
  '.tsx',
])

/**
 * 判断文件是否属于 Oxlint / ESLint 的共同处理范围
 */
export function isLintableFile(filePath: string): boolean {
  return LINTABLE_EXTENSIONS.has(path.extname(filePath).toLowerCase())
}
