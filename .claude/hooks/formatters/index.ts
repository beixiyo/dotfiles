import fs from 'node:fs'
import path from 'node:path'

import { runDprint } from './dprint'
import { runEslint } from './eslint'
// import { runOxfmt } from './oxfmt'
import { isLintableFile, runOxlint } from './oxlint'
import { runPrettier } from './prettier'
import { runVvMcp } from './vv-mcp'

const CODE_EXTENSIONS = new Set([
  '.html', '.js', '.jsx', '.ts', '.tsx', '.vue', '.svelte',
  '.css', '.scss', '.less',
  '.c', '.cc', '.cpp', '.cs',
  '.go', '.java', '.kt', '.kts', '.rs', '.swift',
  '.py', '.rb',
])

/**
 * 按固定优先级处理单个写入文件
 *
 * 1. Oxlint 或 ESLint 二选一
 * 2. 暂时关闭，格式化得太丑了。Oxfmt 负责 JSX / TSX 中的 Tailwind 排序
 * 3. dprint 优先，Prettier 兜底
 * 4. vv-mcp 最后通过 Neovim LSP 修复最终文件
 */
export function formatFile(filePath: string, cwd: string): void {
  if (!CODE_EXTENSIONS.has(path.extname(filePath).toLowerCase())) return
  if (!fs.existsSync(filePath)) return

  if (isLintableFile(filePath)) {
    runOxlint(filePath, cwd) || runEslint(filePath, cwd)
  }

  // runOxfmt(filePath, cwd)
  runDprint(filePath, cwd) || runPrettier(filePath, cwd)
  runVvMcp(filePath, cwd)
}
