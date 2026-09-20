/**
 * Claude Code hooks 移植
 *
 * - Stop             → agent_settled：tmux AI 状态置 done + 桌面完成通知
 * - PostToolUse      → tool_result(write/edit)：跑 ~/.claude/hooks/post-write-code.ts
 *                      格式化管线（喂给它 Claude 形状的 stdin JSON，复用现有实现）
 */
import type { ExtensionAPI } from '@earendil-works/pi-coding-agent'
import { fireAndForget, runDetached } from './lib/proc'

const POST_WRITE_HOOK = '~/.claude/hooks/post-write-code.ts'

export default function(pi: ExtensionAPI) {
  /** Stop hook：agent 结束且不会自动继续（重试/压缩/排队都完成后才触发） */
  pi.on('agent_settled', async () => {
    fireAndForget(
      [
        'export AI_AGENT_NAME=\'Pi\' NOTIFY_APP_NAME=pi NOTIFY_SOUND=1 NOTIFY_DESKTOP=1',
        'bash ~/.config/tmux/scripts/ai-status.sh done "$TMUX_PANE"',
        'bash ~/.zsh/notify/main.sh',
      ].join('; '),
    )
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
