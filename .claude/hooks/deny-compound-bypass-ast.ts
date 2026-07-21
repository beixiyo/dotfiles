#!/usr/bin/env bun
/**
 * PreToolUse hook（AST 版）：通用权限管控（Bash + Read）
 *
 * AST 优先 + 正则兜底：tree-sitter-bash 解析成结构做白名单判定，
 * 解析不可用（缺 web-tree-sitter / 解析报错 / 命令过长）时自动回退正则引擎。
 * 需依赖：web-tree-sitter + tree-sitter-wasms（在本目录 bun install）
 *
 * AST 依赖被隔离在 ast-engine.ts（动态 import），与正则版零耦合
 */
import { run } from './lib/runtime.ts'
import { collectHitsRegex } from './lib/regex-engine.ts'
import { collectHitsAst } from './lib/ast-engine.ts'

await run(await Bun.stdin.text(), async ctx => (await collectHitsAst(ctx)) ?? collectHitsRegex(ctx))
