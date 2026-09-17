/**
 * Ask User — 把扩展 UI 对话框暴露为 agent 可调用的工具
 *
 * pi 核心没有内置的"问用户"工具（交互模型是聊天文本本身），本扩展补齐该能力：
 * - 无 options → ui.input 文本输入框（用户填入）
 * - 有 options → ui.select 列表选择
 * - 非交互模式（-p / rpc / json 无 UI）→ 返回错误提示，不挂起
 * - 用户取消（Esc/空选）→ 明确告知模型不要重试，改用纯文本提问
 */
import type { ExtensionAPI, ToolDefinition } from '@earendil-works/pi-coding-agent'
import { Type } from 'typebox'

const parameters = Type.Object({
  question: Type.String({ description: '要问用户的问题，简短具体' }),
  options: Type.Optional(Type.Array(Type.String(), {
    description: '提供则弹单选列表；省略则弹自由文本输入框',
  })),
  placeholder: Type.Optional(Type.String({
    description: '文本输入框的占位提示（提供 options 时忽略）',
  })),
})

const tool: ToolDefinition<typeof parameters> = {
  name: 'ask_user',
  label: '问用户',
  description:
    '弹窗向用户提问并等待回答。适用于只有用户才知道的信息（偏好、凭证位置、歧义需求、多个可行方案间的抉择）；凡能通过其他工具自行查到的信息不要问用户',
  promptSnippet: '需要用户提供只有本人知道的信息时，用弹窗工具 ask_user 提问',
  parameters,

  async execute(_toolCallId, params, signal, _onUpdate, ctx) {
    if (!ctx.hasUI) {
      return {
        content: [{
          type: 'text',
          text: 'ask_user 在非交互模式下不可用（无对话框 UI），请改用纯文本向用户提问。',
        }],
        isError: true,
        details: undefined,
      }
    }

    let answer: string | undefined
    if (params.options && params.options.length > 0) {
      answer = await ctx.ui.select(params.question, params.options)
    }
    else {
      answer = await ctx.ui.input(params.question, params.placeholder)
    }

    if (signal?.aborted) {
      return {
        content: [{ type: 'text', text: '弹窗已被中止' }],
        isError: true,
        details: undefined,
      }
    }

    const text = answer === undefined
      ? '用户关闭了弹窗且未作答。不要重试弹窗，改用纯文本提问或自行选择合理默认值继续'
      : `用户回答：${answer}`

    return { content: [{ type: 'text', text }], details: undefined }
  },
}

export default function(pi: ExtensionAPI) {
  pi.registerTool(tool)
}
