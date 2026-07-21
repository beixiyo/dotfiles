import { expandHome, SENSITIVE } from './paths.ts'
import { isGitReadonly } from './git.ts'
import type { Ctx, Hit, HookDecision, HookOutput } from './types.ts'

/**
 * PreToolUse hook 运行时：与具体引擎解耦
 *
 * 把「怎么产出命中」（正则 / AST）交给调用方注入的 collector，本模块只负责：
 *   解析输入 → 分发 Bash/Read → 决策（deny 优先 + Codex 分级）→ 打印 → exit
 *
 * Codex ask 兼容性说明（最后验证：2026-07-18，codex-cli 0.144.5，仍未变）
 * - Claude Code 支持 PreToolUse 返回 permissionDecision: 'ask'，由客户端弹出审批
 * - Codex schema 能解析 'ask'，但运行时 output_parser 显式判其 unsupported（放行 + warning），
 *   PermissionRequest hook 也只有 allow/deny——即整个 hook 体系没有任何触发原生审批的路径
 * - 故 Codex 下无「弹审批」中间态，只有放行或硬 deny 二选一：
 *     · 危险命令（关机/磁盘/pipe-to-shell、systemctl 写、敏感文件读、env dump、危险 rm）→ 升级 deny 硬拦
 *     · git 写操作 → 静默放行（codexAllow）；Claude Code 下则返回 ask 弹审批
 *     · 普通 rm/rmdir → 两端都静默放行；危险 rm/rmdir → Claude ask、Codex deny
 * - 本机 Codex 使用 approval_policy=never + danger-full-access。这里的「静默放行」就是 hook
 *   不输出决策并 exit 0，不存在后续审批或沙箱兜底
 *
 * 相关上游记录：
 * - openai/codex#28437（open）：Support PreToolUse permissionDecision: ask for native approval prompts
 * - openai/codex#25555（open）：Hook output schemas allow values later rejected by parser
 * - openai/codex#27833（open）：PreToolUse deny 对 apply_patch 不生效——文件写入类 deny 拦不住，本 hook 的防护对 Bash 才可靠
 * - openai/codex#20702 / #20756 / #26422（closed）：更早的 ask / schema 对齐请求，均未落地 ask 审批
 */

/** Bash 命中收集器：由各 hook 注入（正则 / AST 优先+正则兜底） */
export type BashCollector = (ctx: Ctx) => Promise<Hit[]> | Hit[]

/**
 * 汇总命中 → 最终决策；null 表示放行
 *   任一 deny 级命中 → 整条拦死。否则 Claude 走 ask（弹审批）。
 *   Codex 无审批弹窗：仅当全部 ask 命中都标 codexAllow（git 写）才静默放行；
 *   一旦混入非 codexAllow 的 ask（systemctl / 敏感读 / env dump / 危险 rm）则整条 deny
 */
const decide = (hits: Hit[], isCodex: boolean): HookOutput | null => {
  // git 写规则里剔除只读子命令（git stash list / git branch / git remote -v 等）
  const effective = hits.filter(h => !(h.reason.startsWith('git') && isGitReadonly(h.segment)))
  if (effective.length === 0) return null

  // 按出现位置排序，再按「子命令片段」去重，让复合命令里每段被拦的子命令都呈现
  effective.sort((a, b) => a.index - b.index)
  const seen = new Set<string>()
  const lines = effective
    .filter(({ segment }) => {
      if (seen.has(segment)) return false
      seen.add(segment)
      return true
    })
    .map(({ reason, segment }) => `${reason}｜命中：${segment}`)

  const resolved: HookDecision = effective.some(h => h.level === 'deny')
    ? 'deny'
    : isCodex
      ? (effective.every(h => h.codexAllow) ? 'allow' : 'deny')
      : 'ask'

  return resolved === 'allow' ? null : { decision: resolved, reason: lines.join('\n') }
}

/** Read：敏感路径保护 */
const evaluateRead = (ctx: Ctx): HookOutput | null => {
  if (!ctx.filePath) return null

  const normalized = expandHome(ctx.filePath)
  for (const { re, reason } of SENSITIVE) {
    if (re.test(normalized)) return { decision: ctx.isCodex ? 'deny' : 'ask', reason: `${reason}｜命中：${normalized}` }
  }

  return null
}

/** 解析 PreToolUse 输入并给出决策；返回 null 表示放行（静默 exit 0） */
export const evaluate = async (rawInput: string, collectBash: BashCollector): Promise<HookOutput | null> => {
  let data: { tool_name?: string; tool_input?: Record<string, unknown>; turn_id?: unknown; cwd?: unknown }
  try {
    data = JSON.parse(rawInput)
  }
  catch {
    return null
  }

  const toolName = data?.tool_name ?? ''
  const toolInput = data?.tool_input ?? {}
  const ctx: Ctx = {
    cmd: (toolInput.command as string) ?? '',
    filePath: (toolInput.file_path as string) ?? '',
    cwd: typeof data?.cwd === 'string' && data.cwd ? data.cwd : process.cwd(),
    isCodex: typeof data?.turn_id === 'string',
  }

  if (toolName === 'Bash') return ctx.cmd ? decide(await collectBash(ctx), ctx.isCodex) : null
  if (toolName === 'Read') return evaluateRead(ctx)

  return null
}

/** 跑一次：出决策 → 打印 PreToolUse JSON（放行则静默）→ exit 0 */
export const run = async (rawInput: string, collectBash: BashCollector): Promise<never> => {
  const out = await evaluate(rawInput, collectBash)
  if (out) {
    console.log(JSON.stringify({
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        permissionDecision: out.decision,
        permissionDecisionReason: out.reason,
      },
    }))
  }

  process.exit(0)
}
