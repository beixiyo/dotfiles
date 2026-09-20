/**
 * Permission Gate — 壳调用 ~/.claude/hooks/deny-compound-bypass-ast.ts 权限引擎
 *
 * 与 Claude Code / Codex 共用同一引擎与规则（单一事实源）：
 * - bash 工具 → 引擎 Bash 分支：危险命令（关机/磁盘/pipe-to-shell/eval 注入/危险 rm）deny；
 *   git 写、敏感读等 → ask
 * - read 工具 → 引擎 Read 分支：敏感路径（.env 系列、.ssh、.gnupg、.aws、.netrc）→ ask
 * - write/edit 工具 → 借道引擎 Read 分支复用同一份 SENSITIVE 规则（引擎本身不分发写入类工具名，
 *   这里以 file_path 走 Read 判定，敏感路径写入 → ask 弹确认）
 * - ask：交互模式弹确认框 + 桌面通知；-p 非交互模式无人审批，一律拦截
 * - 引擎静默输出 = 放行（引擎故障同样 fail-open，与其在 Claude/Codex 下的语义一致）
 */
import type { ExtensionAPI } from '@earendil-works/pi-coding-agent'
import { fireAndForget, runDetached } from './lib/proc'

const ENGINE = '~/.claude/hooks/deny-compound-bypass-ast.ts'
const ENGINE_TIMEOUT_MS = 15_000

interface EngineOutput {
  hookSpecificOutput?: {
    permissionDecision?: string
    permissionDecisionReason?: string
  }
}

function askEngine(payload: object): Promise<EngineOutput | null> {
  return runDetached(`bun run ${ENGINE}`, { input: JSON.stringify(payload), waitMs: ENGINE_TIMEOUT_MS })
    .then((result) => {
      if (!result) return null
      try {
        return JSON.parse(result.stdout) as EngineOutput
      }
      catch {
        return null
      }
    })
}

function notifyNeedYou(): void {
  fireAndForget('NOTIFY_APP_NAME=pi bash ~/.zsh/notify/main.sh \'Pi needs you\'')
}

export default function(pi: ExtensionAPI) {
  pi.on('tool_call', async (event, ctx) => {
    const input = event.input as Record<string, unknown> | undefined
    let payload: object | undefined

    if (event.toolName === 'bash') {
      payload = {
        tool_name: 'Bash',
        tool_input: { command: String(input?.command ?? '') },
        cwd: ctx.cwd,
      }
    }
    else if (event.toolName === 'read' || event.toolName === 'write' || event.toolName === 'edit') {
      /** write/edit 借道 Read 分支：file_path 走同一份 SENSITIVE 规则 */
      payload = {
        tool_name: 'Read',
        tool_input: { file_path: String(input?.path ?? input?.file_path ?? '') },
        cwd: ctx.cwd,
      }
    }

    if (!payload) return undefined

    const decision = (await askEngine(payload))?.hookSpecificOutput
    if (!decision?.permissionDecision) return undefined

    const reason = decision.permissionDecisionReason ?? decision.permissionDecision

    if (decision.permissionDecision === 'deny') {
      return { block: true, reason }
    }

    if (!ctx.hasUI) {
      return { block: true, reason: `${reason} (non-interactive mode, approval unavailable)` }
    }

    notifyNeedYou()
    const choice = await ctx.ui.select(`⚠️ Permission approval\n\n${reason}\n\nAllow execution?`, ['Yes', 'No'])
    return choice === 'Yes' ? undefined : { block: true, reason: 'Blocked by user' }
  })
}
