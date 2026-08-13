#!/usr/bin/env bun
/**
 * PostToolUse hook: 写入代码文件后按优先级运行格式化与 Neovim LSP 修复
 *
 * 统一适配两种 hook 客户端的入参——先归一化为「待格式化文件列表」，下游只有一套处理：
 *   - Claude Code：Write / Edit / MultiEdit → tool_input.file_path（单文件）
 *   - Codex：apply_patch → tool_input.command 承载 patch 文本，解析其
 *     `*** Add/Update/Delete File:` 与 `*** Move to:` 指令取改动文件（可多文件）
 *
 * 处理顺序：Oxlint / ESLint → Oxfmt → dprint / Prettier → vv-mcp
 * 其中 Oxlint 与 ESLint、dprint 与 Prettier 都是按可执行文件存在情况二选一
 * 注：同步读到 stdin EOF，天然 drain stdin——避开 Codex PostToolUse
 *     不读 stdin 就 Broken pipe 的坑（openai/codex#32667）
 */

import path from 'node:path'

import { formatFile } from './formatters'
import { readStdin } from './lib/process'

const data = parseInput(readStdin())
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

// ── 类型 ──────────────────────────────────────────────────────

type HookInput = {
  cwd?: string
  tool_name?: string
  tool_input?: {
    file_path?: string
    command?: string
  }
}
