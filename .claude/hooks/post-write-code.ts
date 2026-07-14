#!/usr/bin/env bun
/**
 * PostToolUse hook: 写入代码文件后依次运行 ESLint 与 Neovim LSP 自动修复
 *
 * ESLint 仅处理 JS/TS；vv-mcp 处理当前 Neovim 实例中已连接 LSP 的代码文件
 */

import fs from 'node:fs'
import path from 'node:path'

const input = await Bun.stdin.text()

let filePath = ''
let cwd = process.cwd()

try {
  const data = JSON.parse(input)
  cwd = data?.cwd ?? cwd
  filePath = data?.tool_input?.file_path ?? ''
}
catch {
  process.exit(0)
}

if (!filePath) process.exit(0)

filePath = path.resolve(cwd, filePath)

const codeExtensions = new Set([
  '.html', '.js', '.jsx', '.ts', '.tsx', '.vue', '.svelte',
  '.css', '.scss', '.less',
  '.c', '.cc', '.cpp', '.cs',
  '.go', '.java', '.kt', '.kts', '.rs', '.swift',
  '.py', '.rb', '.lua',
])

if (!codeExtensions.has(path.extname(filePath).toLowerCase())) process.exit(0)

const findExecutable = (startDir: string, name: string): string | null => {
  let dir = startDir
  while (dir !== path.parse(dir).root) {
    const executable = path.join(dir, 'node_modules', '.bin', name)
    if (fs.existsSync(executable)) return executable
    dir = path.dirname(dir)
  }
  return null
}

if (/\.(js|jsx|ts|tsx)$/.test(filePath)) {
  const eslint = findExecutable(path.dirname(filePath), 'eslint')
  if (eslint) {
    Bun.spawnSync([
      eslint,
      '--fix',
      '--fix-type', 'layout,suggestion,directive',
      '--rule', 'unused-imports/no-unused-imports: off',
      '--rule', 'unused-imports/no-unused-vars: off',
      '--rule', 'prefer-const: off',
      filePath,
    ], {
      cwd: path.dirname(filePath),
      stderr: 'inherit',
    })
  }
}

Bun.spawnSync(['vv-mcp', 'fix', filePath], {
  cwd,
  stdout: 'ignore',
  stderr: 'inherit',
})
