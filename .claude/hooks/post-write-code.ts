#!/usr/bin/env bun
/**
 * PostToolUse hook: 写入代码文件后依次运行 ESLint 与 Neovim LSP 自动修复
 *
 * 统一适配两种 hook 客户端的入参——先归一化为「待格式化文件列表」，下游只有一套处理：
 *   - Claude Code：Write / Edit / MultiEdit → tool_input.file_path（单文件）
 *   - Codex：apply_patch → tool_input.command 承载 patch 文本，解析其
 *     `*** Add/Update/Delete File:` 与 `*** Move to:` 指令取改动文件（可多文件）
 *
 * ESLint 仅处理 JS/TS；vv-mcp 处理当前 Neovim 实例中已连接 LSP 的代码文件
 * 注：await Bun.stdin.text() 读到 EOF，天然 drain stdin——避开 Codex PostToolUse
 *     不读 stdin 就 Broken pipe 的坑（openai/codex#32667）
 */

import fs from 'node:fs'
import path from 'node:path'

const CODE_EXTENSIONS = new Set([
  '.html', '.js', '.jsx', '.ts', '.tsx', '.vue', '.svelte',
  '.css', '.scss', '.less',
  '.c', '.cc', '.cpp', '.cs',
  '.go', '.java', '.kt', '.kts', '.rs', '.swift',
  '.py', '.rb', '.lua',
])

const data = parseInput(await Bun.stdin.text())
if (!data) process.exit(0)

const { cwd, filePaths } = normalizeTargets(data)
if (filePaths.length === 0) process.exit(0)

// 调试/测试：POST_WRITE_DRYRUN=1 只打印归一化后的待格式化路径，不实际跑 formatter
if (process.env.POST_WRITE_DRYRUN) {
  console.log(JSON.stringify(filePaths))
  process.exit(0)
}

for (const filePath of filePaths) formatFile(filePath, cwd)

// ── 输入解析与归一化 ──────────────────────────────────────────

/** 安全解析 hook stdin；非 JSON 直接放弃（返回 null → 静默退出） */
function parseInput(raw: string): HookInput | null {
  try {
    return JSON.parse(raw) as HookInput
  }
  catch {
    return null
  }
}

/**
 * 把不同客户端的 tool_input 归一化为「待格式化的绝对路径列表」（去重、相对路径按 cwd 解析）
 */
function normalizeTargets(data: HookInput): { cwd: string; filePaths: string[] } {
  const cwd = data.cwd ?? process.cwd()
  const toolInput = data.tool_input ?? {}
  const targets = new Set<string>()

  // Claude Code：Write / Edit / MultiEdit 单文件
  if (typeof toolInput.file_path === 'string' && toolInput.file_path) {
    targets.add(toolInput.file_path)
  }

  // Codex apply_patch：从 patch 文本解析改动文件（可多文件）
  if (typeof toolInput.command === 'string' && isPatchText(toolInput.command)) {
    for (const file of parsePatchFiles(toolInput.command)) targets.add(file)
  }

  const filePaths = [...targets].map(file => path.resolve(cwd, file))
  return { cwd, filePaths }
}

/** 是否像 apply_patch 的 patch 文本（起始标记或任一文件指令，兼容 heredoc 包裹） */
function isPatchText(command: string): boolean {
  return /^\*\*\* (?:Begin Patch|Add File:|Update File:|Delete File:)/m.test(command)
}

/**
 * 解析 patch 文本，返回改动后仍存在、需格式化的文件路径
 *   Add / Update File → 收录；Move to → 覆盖前一条 Update 的目标（rename 后新路径）；
 *   Delete File → 跳过（文件已不存在）
 */
function parsePatchFiles(patch: string): string[] {
  const files: string[] = []
  let pending: string | null = null

  const flush = (): void => {
    if (pending !== null) {
      files.push(pending)
      pending = null
    }
  }

  for (const line of patch.split('\n')) {
    const add = line.match(/^\*\*\* Add File: (.+?)\s*$/)
    const update = line.match(/^\*\*\* Update File: (.+?)\s*$/)
    const move = line.match(/^\*\*\* Move to: (.+?)\s*$/)
    const remove = line.match(/^\*\*\* Delete File: (.+?)\s*$/)

    if (add) {
      flush()
      files.push(add[1])
    }
    else if (update) {
      flush()
      pending = update[1]
    }
    else if (move) {
      pending = move[1]
    }
    else if (remove) {
      flush()
    }
  }

  flush()
  return files
}

// ── 格式化处理 ────────────────────────────────────────────────

/** 对单个文件依次跑 ESLint（仅 JS/TS）与 vv-mcp LSP 修复 */
function formatFile(filePath: string, cwd: string): void {
  if (!CODE_EXTENSIONS.has(path.extname(filePath).toLowerCase())) return
  if (!fs.existsSync(filePath)) return

  if (/\.(?:js|jsx|ts|tsx)$/.test(filePath)) runEslintFix(filePath)

  Bun.spawnSync(['vv-mcp', 'fix', filePath], {
    cwd,
    stdout: 'ignore',
    stderr: 'inherit',
  })
}

/** 就近查找并运行本地 ESLint（沿目录上溯找 node_modules/.bin/eslint） */
function runEslintFix(filePath: string): void {
  const eslint = findExecutable(path.dirname(filePath), 'eslint')
  if (!eslint) return

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

/** 从 startDir 逐级上溯，找 node_modules/.bin/<name> 可执行文件 */
function findExecutable(startDir: string, name: string): string | null {
  let dir = startDir
  while (dir !== path.parse(dir).root) {
    const executable = path.join(dir, 'node_modules', '.bin', name)
    if (fs.existsSync(executable)) return executable
    dir = path.dirname(dir)
  }
  return null
}

// ── 类型 ──────────────────────────────────────────────────────

type HookInput = {
  cwd?: string
  tool_name?: string
  tool_input?: {
    file_path?: string
    command?: string
  }
}
