/**
 * Slash Anywhere — 句中命令与 skill 补全（/ Tab 手动 + $ 自动触发）
 *
 * pi 内置补全只在「当前行行首打 /」时给命令建议；pi-tui 的
 * setAutocompleteTriggerCharacters 显式过滤 '/'，扩展无法让句中 / 自动触发，
 * 因此提供两条触发通道（Codex 用 $、Claude Code 用句中 / 的折中）：
 * - 句中空白后打 $xxx → 自动弹层（$ 不在过滤名单）
 * - 句中空白后打 /xxx 再按 Tab → 手动弹层（force 路径不受过滤影响）
 * - 建议来自 getCommands()（命令/prompt/skill），选中后统一替换为 "/命令 " 形态
 * - 行首 / 场景原样委托内置 provider，行为不变（含参数补全）
 *
 * 注：pi 只执行「整条消息以 / 开头」的命令；句中补全产物是文本引用（与 Claude Code 一致）
 */
import type { ExtensionAPI } from '@earendil-works/pi-coding-agent'
import type { AutocompleteItem, AutocompleteProvider } from '@earendil-works/pi-tui'
import { appendFileSync } from 'node:fs'

/** 光标前末尾的句中 token（/ 或 $ 开头，符号前是空白），不匹配行首（行首由内置处理） */
const MID_TOKEN_RE = /\s([/$]\S*)$/

function debug(...args: unknown[]): void {
  if (!process.env.SLASH_DEBUG) return
  try {
    appendFileSync('/tmp/slash-debug.log', `${new Date().toISOString()} ${args.join(' ')}\n`)
  }
  catch {}
}

let cachedCommands: AutocompleteItem[] | null = null

export default function(pi: ExtensionAPI) {
  pi.on('session_start', (_event, ctx) => {
    if (typeof ctx.ui.addAutocompleteProvider !== 'function') return

    ctx.ui.addAutocompleteProvider((current): AutocompleteProvider => {
      const commandItems = (): AutocompleteItem[] => {
        if (!cachedCommands) {
          cachedCommands = pi.getCommands().map((cmd) => ({
            value: cmd.name,
            label: cmd.name,
            ...(cmd.description ? { description: cmd.description } : {}),
          }))
        }
        return cachedCommands
      }

      return {
        triggerCharacters: Array.from(new Set(['$', ...(current.triggerCharacters ?? ['@', '#'])])),

        async getSuggestions(lines, cursorLine, cursorCol, options) {
          const before = (lines[cursorLine] ?? '').slice(0, cursorCol)
          debug('getSuggestions', JSON.stringify(before), 'force:', options.force)

          // 行首 /（当前行以 / 开头）→ 内置原路径（命令名 + 参数补全）
          if (before.startsWith('/')) {
            return current.getSuggestions(lines, cursorLine, cursorCol, options)
          }

          const match = before.match(MID_TOKEN_RE)
          if (!match) {
            return current.getSuggestions(lines, cursorLine, cursorCol, options)
          }

          const token = match[1]
          const query = token.slice(1).toLowerCase()
          const items = commandItems().filter((item) => item.value.toLowerCase().includes(query))
          if (items.length === 0) return null
          return { items, prefix: token }
        },

        applyCompletion(lines, cursorLine, cursorCol, item, prefix) {
          // @ 文件 / 引号路径 / 含子斜杠的路径前缀 → 内置处理
          if (!/^[/$]/.test(prefix) || prefix.slice(1).includes('/') || prefix.startsWith('@') || prefix.startsWith('"')) {
            return current.applyCompletion(lines, cursorLine, cursorCol, item, prefix)
          }

          // 命令替换：token（/xx 或 $xx）统一替换为 "/命令 "，光标移到末尾
          const line = lines[cursorLine] ?? ''
          const beforePrefix = line.slice(0, cursorCol - prefix.length)
          const afterCursor = line.slice(cursorCol)
          const newLines = [...lines]
          newLines[cursorLine] = `${beforePrefix}/${item.value} ${afterCursor}`
          return {
            lines: newLines,
            cursorLine,
            cursorCol: beforePrefix.length + item.value.length + 2,
          }
        },
      }
    })
  })

  /** 切换/新建 session 时命令集可能变化，清缓存 */
  pi.on('session_start', () => {
    cachedCommands = null
  })
}
