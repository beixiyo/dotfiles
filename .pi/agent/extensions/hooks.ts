/**
 * Claude Code hooks 移植
 *
 * - agent_settled    → Stop：settings.json `customHooks.agentSettled` 配置的命令（tmux 状态 + 完成通知）
 * - ui_prompt_start  → 阻塞式提问/权限确认：settings.json `customHooks.uiPrompt` 配置的命令（"needs you" 通知）
 * - tool_result      → PostToolUse(write/edit)：跑 ~/.claude/hooks/post-write-code.ts
 *                      格式化管线（喂给它 Claude 形状的 stdin JSON，复用现有实现）
 *
 * 通知类命令从 stdin 拿到 JSON（字段见 {@link HookPayload}）；其中 `context` 与 Claude 侧
 * 的“AI 标题 + 最后一次输入”同形，~/.zsh/notify/context.sh 会直接作为通知正文
 *
 * 不通知的场景：非 TUI（-p / rpc）、pi-subagents 的后台子 agent 进程（PI_SUBAGENT_CHILD=1）
 */
import type { ExtensionAPI, ExtensionContext } from '@earendil-works/pi-coding-agent'
import { type HookName, readHookCommands } from './lib/hooks-config'
import { fireAndForget, runDetached } from './lib/proc'

const POST_WRITE_HOOK = '~/.claude/hooks/post-write-code.ts'
const LAST_PROMPT_MAX = 50
const PROMPT_TITLE_MAX = 100

export default function(pi: ExtensionAPI) {
  /** 仅 agent 运行期间的弹窗才是“模型在等你”；用户自己开的 /yank 等选择器不通知 */
  let running = false

  pi.on('agent_start', async () => {
    running = true
  })

  /** Stop hook：agent 结束且不会自动继续（重试/压缩/排队都完成后才触发） */
  pi.on('agent_settled', async (_event, ctx) => {
    running = false
    runHooks('agentSettled', ctx, {
      hook_event_name: 'Stop',
      context: buildContext(ctx),
    })
  })

  /** 阻塞式 UI 弹窗（ask_user、权限确认等）开始等待用户 */
  pi.on('ui_prompt_start', async (event, ctx) => {
    if (!running) return

    const promptTitle = flatten(event.title ?? '', PROMPT_TITLE_MAX)
    runHooks('uiPrompt', ctx, {
      hook_event_name: 'UIPrompt',
      prompt_kind: event.kind,
      context: buildContext(ctx, promptTitle || 'Waiting for your input'),
    })
  })

  /** PostToolUse(Write|Edit) hook：写入成功后按现有管线格式化 */
  pi.on('tool_result', async (event, ctx) => {
    if (event.toolName !== 'write' && event.toolName !== 'edit') return
    if (event.isError) return

    const filePath = (event.input as Record<string, unknown> | undefined)?.path
    if (typeof filePath !== 'string' || filePath === '') return

    const payload = JSON.stringify({
      tool_name: event.toolName === 'write' ? 'Write' : 'Edit',
      tool_input: { file_path: filePath },
      cwd: ctx.cwd,
    })

    await runDetached(`bun run ${POST_WRITE_HOOK}`, { input: payload, waitMs: 60_000 })
  })
}

/** 执行 settings.json 里配置的 hook 命令（射后不理） */
function runHooks(name: HookName, ctx: ExtensionContext, extra: Record<string, unknown>): void {
  if (!ctx.hasUI) return
  if (process.env.PI_SUBAGENT_CHILD === '1') return

  const commands = readHookCommands(name)
  if (commands.length === 0) return

  const payload: HookPayload = {
    session_id: ctx.sessionManager.getSessionId(),
    transcript_path: ctx.sessionManager.getSessionFile(),
    cwd: ctx.cwd,
    ...extra,
  }
  const input = JSON.stringify(payload)

  for (const cmd of commands) fireAndForget(cmd, input)
}

/**
 * 通知正文：会话名（autoRename 生成）+ 第二行
 * 第二行默认取用户最后一次输入，与 Claude 侧 ai-title + last-prompt 同构
 */
function buildContext(ctx: ExtensionContext, secondLine?: string): string {
  const title = ctx.sessionManager.getSessionName()?.trim()
  const second = secondLine ?? lastUserPrompt(ctx)
  return [title, second].filter(Boolean).join('\n')
}

/** 当前分支上最后一条用户消息的文本，压成单行并截断 */
function lastUserPrompt(ctx: ExtensionContext): string {
  const branch = ctx.sessionManager.getBranch()
  for (let i = branch.length - 1; i >= 0; i--) {
    const entry = branch[i]
    if (entry.type !== 'message' || entry.message.role !== 'user') continue

    const content = entry.message.content
    const text = typeof content === 'string'
      ? content
      : content.map((part) => part.type === 'text' ? part.text : '').join(' ')
    return flatten(text, LAST_PROMPT_MAX)
  }
  return ''
}

function flatten(text: string, max: number): string {
  return text.replace(/\s+/g, ' ').trim().slice(0, max)
}

/** hook 命令 stdin JSON：公共字段对齐 Claude Code，其余为 pi 扩展字段 */
interface HookPayload {
  session_id: string
  transcript_path?: string
  cwd: string
  hook_event_name?: string
  prompt_kind?: string
  /** 通知正文，多行；context.sh 优先使用 */
  context?: string
}
