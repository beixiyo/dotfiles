#!/usr/bin/env bun
/**
 * PreToolUse hook（正则版）：通用权限管控（Bash + Read）
 *
 * 只走正则引擎，零运行时依赖——不 import ast-engine，也不需要 web-tree-sitter。
 * 不想用 AST 的人可只保留：runtime / regex-engine / paths / shell / git / reasons / types
 * AST 版见同目录 deny-compound-bypass-ast.ts
 */
import { run } from './lib/runtime.ts'
import { collectHitsRegex } from './lib/regex-engine.ts'

await run(await Bun.stdin.text(), collectHitsRegex)
