/**
 * Statusline — 声明式配置的彩色 footer（色板参照 tokyonight-pretty_cat.vim）
 *
 * ════════════════════ 配置方式 ════════════════════
 *
 * 所有可调项集中在下方【配置区】：
 * - LEFT_SEGMENTS / RIGHT_SEGMENTS：段落声明数组，按序渲染；删一行即隐藏该段，
 *   换序即调整显示顺序；某段无数据（如不在 git 仓库、未命名会话）时自动跳过
 * - color 三种写法：
 *   1. 主题语义色（ThemeColor，如 'text'/'muted'/'success'，跟随 pi 主题）
 *   2. 真彩 hex（如 '#4aa5f0'，直接输出 24-bit 色；终端仅支持 256 色时自动降级最近色）
 *   3. 'auto'——按用量百分比自动变色，仅右侧用量段（context/quota5h/quotaWeekly）允许，
 *      阈值与三档颜色见 AUTO_LEVELS
 * - 窄终端时 RIGHT_SEGMENTS 从数组尾部开始逐段丢弃，左侧永远保留
 *
 * 配额数据来自 GLM Coding Plan（zai），key 只读 ~/.pi/agent/auth.json；
 * MCP 状态行由 ~/.config/mcp.json 的 mcpFooterStatus: "off" 关闭
 *
 * 输入框徽标（EDITOR_BADGE）：会话名以背景色块嵌入输入框上边框右端，
 * 与 pi-vim 右下角模式标签对称。通过 getEditorComponent() 装饰现有编辑器
 * （如 pi-vim 的 ModalEditor）而非替换，vim 功能不受影响
 *
 * 仅 TUI 模式启用；启动时和每轮结束后刷新配额（节流静默）
 */
import type { ExtensionAPI, Theme, ThemeColor } from '@earendil-works/pi-coding-agent'
import { CustomEditor } from '@earendil-works/pi-coding-agent'
import type { AutocompleteProvider, EditorComponent, TuiMouseEvent, TuiMouseEventResult } from '@earendil-works/pi-tui'
import { truncateToWidth, visibleWidth } from '@earendil-works/pi-tui'
import { readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

// ════════════════════ 配置区 ════════════════════

/** 左侧段落标识（决定取数逻辑） */
type LeftSegmentType = 'model' | 'thinking' | 'branch' | 'sessionName' | 'extensionStatus'

/** 右侧段落标识（决定取数逻辑） */
type RightSegmentType = 'context' | 'quota5h' | 'quotaWeekly' | 'quotaWeeklyReset'

/** 支持 'auto' 变色的用量段 */
type UsageSegmentType = 'context' | 'quota5h' | 'quotaWeekly'

/** 段落颜色：主题语义色 / 真彩 hex / 'auto'（仅用量段允许） */
type SegmentColor = ThemeColor | HexColor | 'auto'

/** 段落标识 → 允许的 color 集合（type 与 color 强制配对，'auto' 仅用量段开放） */
interface SegmentColorMap {
  model: { color: ThemeColor | HexColor }
  thinking: { color: ThemeColor | HexColor }
  branch: { color: ThemeColor | HexColor }
  sessionName: { color: ThemeColor | HexColor }
  extensionStatus: { color: ThemeColor | HexColor }
  context: { color: SegmentColor }
  quota5h: { color: SegmentColor }
  quotaWeekly: { color: SegmentColor }
  quotaWeeklyReset: { color: ThemeColor | HexColor }
}

/** 段落声明：type 与 color 配对约束（'auto' 仅用量段）
 *  通过映射类型钉死每个分支的 type 字面量，防止泛型联合实例化时交叉匹配 */
type SegmentConfig<T extends keyof SegmentColorMap> = { [K in T]: { type: K } & SegmentColorMap[K] }[T]

/** 左侧段落：按序渲染，无数据的段自动跳过（会话名已由输入框徽标显示，需要时加回即可） */
const LEFT_SEGMENTS = [
  { type: 'model', color: '#4aa5f0' },
  { type: 'thinking', color: '#c678dd' },
  { type: 'branch', color: '#98c379' },
  { type: 'extensionStatus', color: '#e5c07b' },
] as const satisfies readonly SegmentConfig<LeftSegmentType>[]

/** 右侧段落：按序渲染；窄终端从尾部逐段丢弃 */
const RIGHT_SEGMENTS = [
  { type: 'context', color: 'auto' },
  { type: 'quotaWeekly', color: 'auto' },
  { type: 'quota5h', color: 'auto' },
  { type: 'quotaWeeklyReset', color: '#d19a66' },
] as const satisfies readonly SegmentConfig<RightSegmentType>[]

/** 'auto' 变色：已用百分比 ≥ dangerAt 用 danger 色、≥ warnAt 用 warn 色、其余 normal */
const AUTO_LEVELS = {
  warnAt: 70,
  dangerAt: 90,
  normal: '#6dc7a8',
  warn: '#e5c07b',
  danger: '#c24038',
} as const satisfies {
  warnAt: number
  dangerAt: number
  normal: ThemeColor | HexColor
  warn: ThemeColor | HexColor
  danger: ThemeColor | HexColor
}

/** 分隔符：段落之间（左/右侧各自）与分隔符颜色 */
const SEPARATORS = {
  left: ' · ',
  right: '  ',
  color: '#7f848e' as ThemeColor | HexColor,
}

/** 隐藏的扩展状态键（footer 不显示，功能本身不受影响） */
const HIDDEN_STATUS_KEYS = ['mcp'] as const

/** GLM Coding Plan 配额查询 */
const QUOTA = {
  /** zai 系 provider → 配额端点 origin（按 auth.json 中实际存在的 provider 取第一个） */
  origins: {
    zai: 'https://api.z.ai',
    'zai-coding-cn': 'https://open.bigmodel.cn',
  },
  /** 刷新节流（毫秒） */
  refreshIntervalMs: 60_000,
  /** 单次请求超时（毫秒） */
  fetchTimeoutMs: 5_000,
} as const

/** 输入框徽标：会话名背景色块，嵌入输入框上边框右端 */
const EDITOR_BADGE = {
  /** 关闭时完全不触碰编辑器组件 */
  enabled: true,
  /** 背景色（hex） */
  bg: '#4aa5f0',
  /** 前景色（hex）；缺省按背景亮度自动取深/浅 */
  fg: undefined as HexColor | undefined,
  /** 徽标最长显示宽度（列，含前后底色空格），超出尾部省略；null = 跟随编辑器渲染宽度 */
  maxWidth: null as number | null,
} as const satisfies { enabled: boolean; bg: HexColor; fg?: HexColor; maxWidth: number | null }

// ════════════════════ 实现 ════════════════════

/** 'auto' 颜色解析：按用量百分比落档；固定色原样返回 */
function resolveColor(color: SegmentColor, pct?: number | null): ThemeColor | HexColor {
  if (color !== 'auto') return color
  if (pct === null || pct === undefined) return AUTO_LEVELS.normal
  return pct >= AUTO_LEVELS.dangerAt
    ? AUTO_LEVELS.danger
    : pct >= AUTO_LEVELS.warnAt
    ? AUTO_LEVELS.warn
    : AUTO_LEVELS.normal
}

/** hex 色判定（类型谓词，收窄 ThemeColor | HexColor） */
function isHexColor(color: ThemeColor | HexColor): color is HexColor {
  return color.startsWith('#')
}

/** 统一着色：hex 走真彩（256 色终端降级最近色），其余走主题语义色 */
function colorize(theme: Theme, color: ThemeColor | HexColor, text: string): string {
  return isHexColor(color) ? hexFg(theme, color, text) : theme.fg(color, text)
}

const HEX_RE = /^#([0-9a-f]{6})$/i

function parseHex(hex: string): [number, number, number] | undefined {
  const match = HEX_RE.exec(hex)
  if (!match) return undefined
  const v = match[1]!
  return [Number.parseInt(v.slice(0, 2), 16), Number.parseInt(v.slice(2, 4), 16), Number.parseInt(v.slice(4, 6), 16)]
}

/** xterm 216 色立方最近色索引 */
function cube256([r, g, b]: [number, number, number]): number {
  return 16 + 36 * Math.round((r / 255) * 5) + 6 * Math.round((g / 255) * 5) + Math.round((b / 255) * 5)
}

function hexFg(theme: Theme, hex: HexColor, text: string): string {
  const rgb = parseHex(hex)
  if (!rgb) return theme.fg('text', text) // 非法 hex 容错：回退主题主色
  return theme.getColorMode() === 'truecolor'
    ? `\x1b[38;2;${rgb[0]};${rgb[1]};${rgb[2]}m${text}\x1b[39m`
    : `\x1b[38;5;${cube256(rgb)}m${text}\x1b[39m`
}

/** 按背景亮度自动取对比前景色（亮底 → 主题深色，暗底 → 亮灰） */
function autoBadgeFg(bg: HexColor): HexColor {
  const rgb = parseHex(bg)
  const lum = rgb ? (0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]) / 255 : 0
  return lum > 0.45 ? '#1e1e2e' : '#c2c2c2'
}

/** 会话名背景色块标签：' 名称 '（前后各留一格底色）
 * 编辑器 factory 只提供 EditorTheme（无颜色模式），改按 COLORTERM 检测；
 * 检测不到时保守输出 256 色索引（truecolor 终端也兼容） */
const TRUECOLOR = /truecolor|24bit/i.test(process.env.COLORTERM ?? '')

/** 徽标最长显示宽度（列），含前后底色空格，名称部分占 maxWidth - 2 */
function badgeLabel(name: string, maxWidth: number): string {
  const text = ` ${truncateToWidth(name, Math.max(1, maxWidth - 2), '…')} `
  const bg = parseHex(EDITOR_BADGE.bg)
  const fg = parseHex(EDITOR_BADGE.fg ?? autoBadgeFg(EDITOR_BADGE.bg))
  if (!bg || !fg) return text
  if (TRUECOLOR) {
    return `\x1b[48;2;${bg[0]};${bg[1]};${bg[2]}m\x1b[38;2;${fg[0]};${fg[1]};${fg[2]}m${text}\x1b[39m\x1b[49m`
  }
  return `\x1b[48;5;${cube256(bg)}m\x1b[38;5;${cube256(fg)}m${text}\x1b[39m\x1b[49m`
}

/** 剩余时间：142h → 5d22h / 3.2h → 3h12m / 40m → 40m */
function fmtDuration(ms: number): string {
  const minutes = Math.max(0, Math.round(ms / 60_000))
  if (minutes < 60) return `${minutes}m`
  const hours = Math.floor(minutes / 60)
  if (hours < 48) return `${hours}h${minutes % 60}m`
  return `${Math.floor(hours / 24)}d${hours % 24}h`
}

/** 从 auth.json 解析 zai 凭证（只读，不写回） */
function resolveZaiAuth(): { origin: string; key: string } | undefined {
  try {
    const auth: unknown = JSON.parse(readFileSync(join(homedir(), '.pi', 'agent', 'auth.json'), 'utf8'))
    const providers = auth && typeof auth === 'object' ? (auth as Record<string, unknown>) : undefined
    for (const [provider, origin] of Object.entries(QUOTA.origins)) {
      const key = providers?.[provider] && typeof providers[provider] === 'object'
        ? (providers[provider] as Record<string, unknown>).key
        : undefined
      if (typeof key === 'string' && key) return { origin, key }
    }
  }
  catch {
    // 无 auth.json 或格式异常：不显示配额
  }
  return undefined
}

async function fetchZaiQuota(auth: { origin: string; key: string }): Promise<unknown> {
  const res = await fetch(`${auth.origin}/api/monitor/usage/quota/limit`, {
    headers: { Authorization: auth.key },
    signal: AbortSignal.timeout(QUOTA.fetchTimeoutMs),
  })
  if (!res.ok) throw new Error(`HTTP ${res.status}`)
  return res.json()
}

/** 装饰现有编辑器：转发全部接口，仅在上边框右端嵌入会话名背景色块
 * 不替换底层实现（pi-vim 的 ModalEditor 等），vim/补全/IME 光标均不受影响 */
class SessionBadgeEditor implements EditorComponent {
  constructor(
    private readonly inner: EditorComponent,
    private readonly getName: () => string | undefined,
  ) {}

  render(width: number): string[] {
    const lines = this.inner.render(width)
    const name = this.getName()
    if (!name || lines.length === 0) return lines
    const label = badgeLabel(name, EDITOR_BADGE.maxWidth ?? width)
    const labelWidth = visibleWidth(label)
    if (labelWidth > width) return lines
    lines[0] = truncateToWidth(lines[0]!, width - labelWidth, '') + label
    return lines
  }

  invalidate(): void {
    this.inner.invalidate()
  }

  handleInput(data: string): void {
    this.inner.handleInput(data)
  }

  handleMouse(event: TuiMouseEvent): TuiMouseEventResult | undefined {
    return this.inner.handleMouse?.(event)
  }

  get wantsKeyRelease(): boolean | undefined {
    return this.inner.wantsKeyRelease
  }

  getText(): string {
    return this.inner.getText()
  }

  setText(text: string): void {
    this.inner.setText(text)
  }

  addToHistory(text: string): void {
    this.inner.addToHistory?.(text)
  }

  insertTextAtCursor(text: string): void {
    this.inner.insertTextAtCursor?.(text)
  }

  getExpandedText(): string {
    return this.inner.getExpandedText?.() ?? this.getText()
  }

  setAutocompleteProvider(provider: AutocompleteProvider): void {
    this.inner.setAutocompleteProvider?.(provider)
  }

  setAutocompleteMaxVisible(maxVisible: number): void {
    this.inner.setAutocompleteMaxVisible?.(maxVisible)
  }

  setPaddingX(padding: number): void {
    this.inner.setPaddingX?.(padding)
  }

  // 宿主读写转发（提交/变更回调、边框色由宿主挂接到编辑器实例上）
  get onSubmit() {
    return this.inner.onSubmit
  }

  set onSubmit(fn: ((text: string) => void) | undefined) {
    this.inner.onSubmit = fn
  }

  get onChange() {
    return this.inner.onChange
  }

  set onChange(fn: ((text: string) => void) | undefined) {
    this.inner.onChange = fn
  }

  get borderColor() {
    return this.inner.borderColor
  }

  set borderColor(fn: ((str: string) => string) | undefined) {
    this.inner.borderColor = fn
  }

  // Focusable 转发（IME 候选窗光标定位）
  get focused(): boolean {
    return (this.inner as unknown as { focused?: boolean }).focused ?? false
  }

  set focused(value: boolean) {
    ;(this.inner as unknown as { focused: boolean }).focused = value
  }

  // ── app 级动作转发（必须）──
  // pi 安装自定义编辑器时按鸭子类型（"actionHandlers" in editor && instanceof Map）
  // 把 app.clear（C-c 清空/双击退出）、app.exit、escape 中断等处理器拷贝到最外层
  // 组件。包装类不暴露这些成员时拷贝被整体跳过，内层编辑器的处理器表为空，
  // 所有 app 级快捷键失效（症状：双击 C-c 无法退出）。转发到 inner 后，
  // pi 写入的处理器由 inner.handleInput 分发时原样读到，包装层零参与
  get actionHandlers(): Map<string, () => void> | undefined {
    return (this.inner as unknown as { actionHandlers?: Map<string, () => void> }).actionHandlers
  }

  get onEscape(): (() => void) | undefined {
    return (this.inner as unknown as { onEscape?: () => void }).onEscape
  }

  set onEscape(fn: (() => void) | undefined) {
    ;(this.inner as unknown as { onEscape?: () => void }).onEscape = fn
  }

  get onCtrlD(): (() => void) | undefined {
    return (this.inner as unknown as { onCtrlD?: () => void }).onCtrlD
  }

  set onCtrlD(fn: (() => void) | undefined) {
    ;(this.inner as unknown as { onCtrlD?: () => void }).onCtrlD = fn
  }

  get onPasteImage(): (() => void) | undefined {
    return (this.inner as unknown as { onPasteImage?: () => void }).onPasteImage
  }

  set onPasteImage(fn: (() => void) | undefined) {
    ;(this.inner as unknown as { onPasteImage?: () => void }).onPasteImage = fn
  }

  get onExtensionShortcut(): ((data: string) => boolean) | undefined {
    return (this.inner as unknown as { onExtensionShortcut?: (data: string) => boolean }).onExtensionShortcut
  }

  set onExtensionShortcut(fn: ((data: string) => boolean) | undefined) {
    ;(this.inner as unknown as { onExtensionShortcut?: (data: string) => boolean }).onExtensionShortcut = fn
  }
}

export default function(pi: ExtensionAPI) {
  let quota: ZaiQuota | undefined
  let requestRender: (() => void) | undefined
  let lastFetch = 0
  let fetching = false

  async function refreshQuota(): Promise<void> {
    if (fetching || Date.now() - lastFetch < QUOTA.refreshIntervalMs) return
    fetching = true
    lastFetch = Date.now()
    try {
      const auth = resolveZaiAuth()
      if (auth) quota = parseZaiQuota(await fetchZaiQuota(auth))
    }
    catch {
      // 静默：保留上次结果，下一轮再试
    }
    finally {
      fetching = false
      requestRender?.()
    }
  }

  pi.on('session_start', async (_event, ctx) => {
    if (ctx.mode !== 'tui') return
    void refreshQuota()

    // 输入框徽标：延迟一拍包装。局部扩展先于 package（pi-vim 等）初始化，
    // 立即读 getEditorComponent() 会拿到 undefined 且随后被 package 覆盖；
    // setTimeout(0) 等全部同步 session_start 跑完后再装饰现有编辑器
    if (EDITOR_BADGE.enabled) {
      setTimeout(() => {
        const existing = ctx.ui.getEditorComponent()
        const base = existing ?? ((tui, theme, kb) => new CustomEditor(tui, theme, kb))
        ctx.ui.setEditorComponent((tui, theme, kb) => new SessionBadgeEditor(base(tui, theme, kb), () => ctx.sessionManager.getSessionName()))
      }, 0)
    }

    ctx.ui.setFooter((tui, theme, footerData) => {
      requestRender = () => tui.requestRender()
      // 分支切换主动重绘；dispose 由 TUI 在替换/关闭 footer 时调用
      const dispose = footerData.onBranchChange(() => tui.requestRender())

      /** 左侧段取文本（extensionStatus 可产出多段），无数据返回空数组 */
      const leftTexts = (cfg: SegmentConfig<LeftSegmentType>): string[] => {
        switch (cfg.type) {
          case 'model':
            return [ctx.model?.name ?? ctx.model?.id ?? 'no-model']
          case 'thinking':
            return [`思考 ${ctx.thinkingLevel ?? 'off'}`]
          case 'branch': {
            const branch = footerData.getGitBranch()
            return branch ? [branch] : []
          }
          case 'sessionName': {
            const name = ctx.sessionManager.getSessionName()
            return name ? [name] : []
          }
          case 'extensionStatus':
            return [...footerData.getExtensionStatuses()]
              .filter(([key]) => !(HIDDEN_STATUS_KEYS as readonly string[]).includes(key))
              .map(([, status]) => status)
        }
      }

      /** 右侧段取文本与用量百分比，无数据返回 undefined */
      const rightText = (cfg: SegmentConfig<RightSegmentType>): { text: string; pct: number | null } | undefined => {
        switch (cfg.type) {
          case 'context': {
            const usage = ctx.getContextUsage()
            if (!usage) return undefined
            const pct = usage.percent
            return { text: pct === null ? 'ctx ?' : `ctx 已用${Math.round(pct)}%`, pct }
          }
          case 'quota5h':
            return quota?.fiveHour
          case 'quotaWeekly':
            return quota?.weekly
          case 'quotaWeeklyReset': {
            const resetsAt = quota?.weekly?.resetsAt
            if (resetsAt === undefined) return undefined
            return { text: `周重置 ${fmtDuration(resetsAt - Date.now())}`, pct: null }
          }
        }
      }

      const render = (width: number): string[] => {
        // ── 左侧：遍历声明，无数据段跳过 ──
        const leftParts = LEFT_SEGMENTS.flatMap((cfg) => leftTexts(cfg).map((text) => colorize(theme, resolveColor(cfg.color), text)))
        const dot = colorize(theme, SEPARATORS.color, SEPARATORS.left)
        const left = ' ' + leftParts.join(dot)

        // ── 右侧：遍历声明；窄终端从尾部逐段丢弃 ──
        const segments = RIGHT_SEGMENTS
          .map((cfg) => {
            const part = rightText(cfg)
            return part ? colorize(theme, resolveColor(cfg.color, part.pct), part.text) : undefined
          })
          .filter((s): s is string => s !== undefined)

        const gap = colorize(theme, SEPARATORS.color, SEPARATORS.right)
        const kept = [...segments]
        while (kept.length > 0) {
          const right = kept.join(gap)
          const pad = width - visibleWidth(left) - visibleWidth(right) - 1
          if (pad >= 1) return [left + ' '.repeat(pad) + right]
          kept.pop()
        }
        return [truncateToWidth(left, width, '')]
      }

      return { render, invalidate() {}, dispose }
    })
  })

  // 每轮结束后配额已变化，刷新一次（内部节流）
  pi.on('turn_end', () => {
    void refreshQuota()
  })
}

// ════════════════════ 内部数据类型 ════════════════════

/** hex 色声明，如 '#4aa5f0'（#RRGGBB） */
type HexColor = `#${string}`

interface QuotaWindow {
  /** footer 显示文本，如 "5h 12.4k/28k" 或 "周 36%" */
  text: string
  /** 已用百分比，用于 'auto' 变色；缺省为 null */
  pct: number | null
  /** 窗口重置时刻（epoch 毫秒），缺省无 */
  resetsAt?: number
}

interface ZaiQuota {
  fiveHour?: QuotaWindow
  weekly?: QuotaWindow
}

/** 单窗口解析：优先响应自带百分比，缺省由计数（currentValue/usage）换算 */
function quotaWindow(prefix: string, limit: Record<string, unknown>): QuotaWindow | undefined {
  let pct = asNumber(limit.percentage)
  if (pct === undefined) {
    const used = asNumber(limit.currentValue)
    const total = asNumber(limit.usage)
    if (used !== undefined && total !== undefined && total > 0) pct = (used / total) * 100
  }
  if (pct === undefined) return undefined
  return { text: `${prefix} 已用${Math.round(pct)}%`, pct, ...withResetsAt(limit) }
}

function withResetsAt(limit: Record<string, unknown>): { resetsAt?: number } {
  const resetsAt = asNumber(limit.nextResetTime)
  return resetsAt !== undefined ? { resetsAt } : {}
}

/** 解析配额响应：unit 3 为 5h 窗口，unit 6 为周窗口 */
function parseZaiQuota(payload: unknown): ZaiQuota {
  const result: ZaiQuota = {}
  const payloadObj = asObject(payload)
  const data = asObject(payloadObj?.data)
  if (payloadObj?.success === false || data === undefined) return result
  const limits = Array.isArray(data.limits) ? data.limits : []
  for (const raw of limits) {
    const limit = asObject(raw)
    if (!limit) continue
    if (limit.type !== 'TOKENS_LIMIT' && limit.type !== 'CREDIT_LIMIT') continue
    if (limit.unit === 3) result.fiveHour = quotaWindow('5h', limit)
    else if (limit.unit === 6) result.weekly = quotaWindow('周', limit)
  }
  return result
}

function asObject(value: unknown): Record<string, unknown> | undefined {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : undefined
}

function asNumber(value: unknown): number | undefined {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : undefined
}
