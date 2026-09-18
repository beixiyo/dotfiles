/**
 * Ask User — 把扩展 UI 对话框暴露为 agent 可调用的工具
 *
 * pi 核心没有内置的"问用户"工具（交互模型是聊天文本本身），本扩展补齐该能力：
 * - 无 options → ui.input 文本输入框（用户填入）
 * - 有 options → ui.custom 组合对话框：上方选项列表 + 底部自定义答案输入框；
 *   ↑↓ 选择、enter 确认（输入框非空时优先提交自定义答案，留空提交选中项），
 *   直接打字进入输入框，esc/ctrl+c 取消
 * - 非交互模式（-p / rpc / json 无 UI）→ 返回错误提示，不挂起
 * - 用户取消（Esc）→ 明确告知模型不要重试，改用纯文本提问
 */
import type { ExtensionAPI, Theme, ToolDefinition } from '@earendil-works/pi-coding-agent'
import type { Component, Focusable, KeybindingsManager } from '@earendil-works/pi-tui'
import { Container, Input, Spacer, Text } from '@earendil-works/pi-tui'
import { Type } from 'typebox'

const parameters = Type.Object({
  question: Type.String({ description: '要问用户的问题，简短具体' }),
  options: Type.Optional(Type.Array(Type.String(), {
    description: '候选选项；用户仍可在弹窗底部输入框自定义答案',
  })),
  placeholder: Type.Optional(Type.String({
    description: '输入框的占位提示（无 options 时为自由输入框，有 options 时为自定义答案输入框）',
  })),
})

/**
 * 选项列表 + 底部自定义答案输入框的组合对话框
 *
 * 单焦点交互：可打印按键、退格、粘贴等全部进输入框；↑↓（跟随
 * tui.select.up/down 绑定）只走列表。enter 语义：输入框非空 → 提交
 * 自定义答案；空 → 提交当前选中项。这样用户无需在两个焦点区之间切换
 */
export class AskUserSelectComponent implements Component, Focusable {
  private readonly container = new Container()
  private readonly listContainer = new Container()
  private readonly input: Input
  private readonly options: readonly string[]
  private selectedIndex = 0
  private _focused = false

  constructor(
    private readonly theme: Theme,
    private readonly kb: KeybindingsManager,
    question: string,
    options: readonly string[],
    placeholder: string | undefined,
    private readonly done: (result: string | undefined) => void,
  ) {
    this.options = options

    this.container.addChild(new Spacer(1))
    this.container.addChild(new Text(theme.fg('accent', theme.bold(question)), 1, 0))
    this.container.addChild(new Spacer(1))
    this.container.addChild(this.listContainer)
    this.container.addChild(new Spacer(1))
    this.input = new Input({
      prompt: '❯ ',
      placeholder: placeholder ?? 'Custom answer (empty = use selection)',
      placeholderStyle: (text) => theme.fg('muted', text),
    })
    this.container.addChild(this.input)
    this.container.addChild(new Spacer(1))
    this.container.addChild(new Text(theme.fg('dim', '↑↓ select · type for custom answer · enter confirm · esc cancel'), 1, 0))
    this.container.addChild(new Spacer(1))
    this.updateList()
  }

  /** Focusable：转发给输入框，IME 候选窗光标定位用 */
  get focused(): boolean {
    return this._focused
  }

  set focused(value: boolean) {
    this._focused = value
    this.input.focused = value
  }

  handleInput(data: string): void {
    if (this.kb.matches(data, 'tui.select.cancel')) {
      this.done(undefined)
      return
    }
    if (this.kb.matches(data, 'tui.select.confirm') || this.kb.matches(data, 'tui.input.submit')) {
      const custom = this.input.getValue().trim()
      if (custom !== '') {
        this.done(custom)
        return
      }
      const selected = this.options[this.selectedIndex]
      if (selected !== undefined) this.done(selected)
      return
    }
    if (this.kb.matches(data, 'tui.select.up')) {
      if (this.selectedIndex > 0) {
        this.selectedIndex--
        this.updateList()
      }
      return
    }
    if (this.kb.matches(data, 'tui.select.down')) {
      if (this.selectedIndex < this.options.length - 1) {
        this.selectedIndex++
        this.updateList()
      }
      return
    }
    // 可打印字符、退格、左右移动、粘贴、撤销等全部交给输入框
    this.input.handleInput(data)
  }

  render(width: number): string[] {
    return this.container.render(width)
  }

  invalidate(): void {
    this.container.invalidate()
  }

  private updateList(): void {
    this.listContainer.clear()
    for (const [index, option] of this.options.entries()) {
      const text = index === this.selectedIndex
        ? this.theme.fg('accent', `→ ${option}`)
        : this.theme.fg('text', `  ${option}`)
      this.listContainer.addChild(new Text(text, 1, 0))
    }
  }
}

const tool: ToolDefinition<typeof parameters> = {
  name: 'ask_user',
  label: '问用户',
  description:
    '弹窗向用户提问并等待回答。适用于只有用户才知道的信息（偏好、凭证位置、歧义需求、多个可行方案间的抉择）；提供 options 时用户既可从列表选择，也可在底部输入框自定义答案；凡能通过其他工具自行查到的信息不要问用户',
  promptSnippet: '需要用户提供只有本人知道的信息时，用弹窗工具 ask_user 提问',
  parameters,

  async execute(_toolCallId, params, signal, _onUpdate, ctx) {
    if (!ctx.hasUI) {
      return {
        content: [{
          type: 'text',
          text: 'ask_user is unavailable in non-interactive mode (no dialog UI). Ask the user in plain text instead.',
        }],
        isError: true,
        details: undefined,
      }
    }

    let answer: string | undefined
    if (params.options && params.options.length > 0) {
      // ui.custom 不支持 abort signal（pi API 限制）：run 被中止时弹窗仍在，
      // 需用户手动 esc 关闭；await 返回后统一由 signal.aborted 分支收尾
      answer = await ctx.ui.custom<string | undefined>(
        (_tui, theme, kb, done) => new AskUserSelectComponent(theme, kb, params.question, params.options!, params.placeholder, done),
      )
    }
    else {
      answer = await ctx.ui.input(params.question, params.placeholder)
    }

    if (signal?.aborted) {
      return {
        content: [{ type: 'text', text: 'Dialog aborted' }],
        isError: true,
        details: undefined,
      }
    }

    const text = answer === undefined
      ? 'The user closed the dialog without answering. Do not retry the dialog; ask in plain text or pick a reasonable default and continue'
      : `User answered: ${answer}`

    return { content: [{ type: 'text', text }], details: undefined }
  },
}

export default function(pi: ExtensionAPI) {
  pi.registerTool(tool)
}
