/**
 * Session Rename — 首轮自动命名 + /rename 手动命令
 *
 * ## 功能
 * - 首轮请求 settle 后，用首轮用户消息自动生成标题（已命名的会话永不覆盖）
 * - /rename <文字>  → 直接以参数命名
 * - /rename         → 从最近几轮对话重新生成标题
 *
 * ## 配置（~/.pi/agent/settings.json，整段可省略，省略时跟随主模型）
 *   {
 *     "autoRename": {
 *       "model": "zai/glm-5-turbo",     // "provider/model" 或 "provider/model:thinking"
 *       "thinkingLevel": "minimal",     // minimal | low | medium | high | xhigh
 *       "maxLen": 24                    // 标题最大字符数
 *     }
 *   }
 * 模型解析顺序：autoRename.model → pi defaultModel → 当前会话模型
 *
 * ## 调试
 * 以 RENAME_DEBUG=1 启动 pi，命名过程写入 DEBUG_LOG；默认关闭零开销
 */
import type { ExtensionAPI, ExtensionContext } from '@earendil-works/pi-coding-agent'
import { appendFileSync, existsSync, readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

// ── 常量 ──────────────────────────────────────────────

/** 调试日志：环境变量开关与写入路径 */
const DEBUG_ENV = 'RENAME_DEBUG'
const DEBUG_LOG = '/tmp/rename-debug.log'

/** 标题生成的模型调用超时（防悬空 promise 无限挂着） */
const TITLE_TIMEOUT_MS = 20_000

/** 标题最大字符数（settings.autoRename.maxLen 的缺省值） */
const DEFAULT_MAX_LEN = 24

/** 自动命名：取首轮用户消息的最大长度 */
const MAX_FIRST_INPUT = 800

/** /rename 重新生成：单条消息截断、总预算、保留的最近轮数（不含首条） */
const MAX_TURN_TEXT = 500
const MAX_CONVERSATION = 2_000
const RECENT_TURNS = 4

/** 合法思考强度（model 引号后缀与 thinkingLevel 配置共用） */
const THINKING_LEVELS = new Set(['minimal', 'low', 'medium', 'high', 'xhigh'])

/** 标题生成指令（给模型的 system prompt） */
const SYSTEM_PROMPT = '你为编码会话生成一个简短标题。只输出标题本身：不加引号、不以标点结尾、不写任何解释或前后缀。'
  + '用与会话内容相同的语言；中文不超过 16 字，英文不超过 10 个词；'
  + '标题要具体到用户能在会话列表里一眼认出这个会话。'

// ── 类型 ──────────────────────────────────────────────

type AutoRenameSettings = {
  model?: string
  thinkingLevel?: string
  maxLen?: number
}

type ModelRef = { provider: string; modelId: string; thinkingLevel: string }

function readSettings(): { defaultProvider?: string; defaultModel?: string; autoRename?: AutoRenameSettings } {
  try {
    const file = join(process.env.PI_CODING_AGENT_DIR ?? join(homedir(), '.pi', 'agent'), 'settings.json')
    if (!existsSync(file)) return {}
    const parsed = JSON.parse(readFileSync(file, 'utf8'))
    return parsed && typeof parsed === 'object' ? parsed : {}
  }
  catch {
    return {}
  }
}

/** 解析 "provider/model" / "provider/model:thinking" / "model"（无前缀时 provider 由 fallback 提供） */
function parseModelRef(spec: string, fallbackProvider?: string, fallbackThinking = 'minimal'): ModelRef | null {
  const trimmed = spec.trim()
  if (!trimmed) return null
  let provider = ''
  let modelId = trimmed

  // 显式 "provider/model" 前缀无条件优先拆分：否则 fallbackProvider 存在时
  // 整串会被误当作 modelId（如 "zai/glm-5-turbo" → modelId 仍带前缀，find 失败）
  const slash = trimmed.indexOf('/')
  if (slash !== -1) {
    provider = trimmed.slice(0, slash).trim()
    modelId = trimmed.slice(slash + 1).trim()
  }
  if (!provider) provider = fallbackProvider ?? ''

  let thinkingLevel = fallbackThinking
  const colon = modelId.lastIndexOf(':')

  if (colon !== -1 && THINKING_LEVELS.has(modelId.slice(colon + 1).trim())) {
    thinkingLevel = modelId.slice(colon + 1).trim()
    modelId = modelId.slice(0, colon).trim()
  }
  if (!provider || !modelId) return null

  return { provider, modelId, thinkingLevel }
}

/** 模型解析：autoRename.model → pi defaultModel → 当前会话模型 */
function resolveModelRef(ctx: ExtensionContext): ModelRef | null {
  const settings = readSettings()
  const thinking = settings.autoRename?.thinkingLevel?.trim()
  const fallbackThinking = thinking && THINKING_LEVELS.has(thinking) ? thinking : 'minimal'

  const spec = settings.autoRename?.model
    ?? (settings.defaultModel ? `${settings.defaultProvider ?? ''}/${settings.defaultModel}` : '')
  const ref = spec ? parseModelRef(spec, settings.defaultProvider, fallbackThinking) : null
  if (ref) return ref

  const current = ctx.model
  if (!current) return null
  return { provider: String(current.provider), modelId: current.id, thinkingLevel: fallbackThinking }
}

/** 标题清洗：剥引号/代码块/换行/句尾标点，硬截断保词边界 */
function cleanTitle(raw: string, maxLen: number): string {
  let title = raw.trim()
    .replace(/^```(?:\w+)?\s*/i, '').replace(/```\s*$/i, '')
    .replace(/^['"「『]+|['"」』]+$/g, '')
    .replace(/\s+/g, ' ')
    .replace(/[。.!！?？~～]+$/g, '')
    .trim()

  if (title.length > maxLen) {
    const cut = title.slice(0, maxLen)
    const lastSpace = cut.lastIndexOf(' ')
    title = (lastSpace > maxLen * 0.6 ? cut.slice(0, lastSpace) : cut).trim()
  }
  return title
}

/** 调用小模型生成标题；失败返回空串（best-effort，绝不打扰主流程）
 * 20s 超时中止，防悬空 promise 无限挂着 */
async function generateTitle(ctx: ExtensionContext, content: string, maxLen: number): Promise<string> {
  const ref = resolveModelRef(ctx)
  debug('ref=', JSON.stringify(ref), 'content.len=', content.length)
  if (!ref || !content.trim()) return ''

  try {
    const model = ctx.modelRegistry.find(ref.provider, ref.modelId)
    const provider = model ? ctx.modelRegistry.getProvider(model.provider) : undefined
    debug('model=', !!model, 'provider=', !!provider)
    if (!model || !provider) return ''

    const auth = await ctx.modelRegistry.getApiKeyAndHeaders(model)
    debug('auth.ok=', auth.ok, 'hasKey=', !!auth.apiKey)
    if (!auth.ok || !auth.apiKey) return ''

    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), TITLE_TIMEOUT_MS)
    try {
      const response = await provider.streamSimple(
        model,
        {
          systemPrompt: SYSTEM_PROMPT,
          messages: [{
            role: 'user',
            content: [{ type: 'text', text: `会话内容：\n${content}` }],
            timestamp: Date.now(),
          }],
        },
        {
          apiKey: auth.apiKey,
          headers: auth.headers,
          env: auth.env,
          reasoning: ref.thinkingLevel,
          signal: controller.signal,
        },
      ).result()

      if (response.stopReason === 'error' || response.stopReason === 'aborted') {
        debug('stopReason=', response.stopReason, 'err=', (response as { errorMessage?: string }).errorMessage)
        return ''
      }

      const text = response.content
        .filter((part): part is { type: 'text'; text: string } => part.type === 'text')
        .map((part) => part.text)
        .join(' ')
      debug('modelText=', JSON.stringify(text))

      return cleanTitle(text, maxLen)
    }
    finally {
      clearTimeout(timer)
    }
  }
  catch (err) {
    debug('threw=', String(err))
    return ''
  }
}

function debug(...args: unknown[]): void {
  if (!process.env[DEBUG_ENV]) return
  try {
    appendFileSync(DEBUG_LOG, `${new Date().toISOString()} ${args.join(' ')}\n`)
  }
  catch {}
}

/** 从会话分支提取对话文本：首轮用户消息（自动命名用） */
function firstUserText(ctx: ExtensionContext): string {
  for (const entry of ctx.sessionManager.getBranch()) {
    if (entry.type !== 'message') continue

    const message = (entry as { message?: { role?: string; content?: unknown } }).message
    if (message?.role !== 'user') continue

    const content = message.content
    const text = typeof content === 'string'
      ? content
      : Array.isArray(content)
      ? content.filter((p): p is { type: 'text'; text: string } => !!p && typeof p === 'object' && (p as { type?: string }).type === 'text')
        .map((p) => p.text).join('\n')
      : ''
    if (text.trim()) return text.trim().slice(0, MAX_FIRST_INPUT)
  }
  return ''
}

/** 最近几轮对话文本（/rename 无参数重新生成用） */
function recentConversationText(ctx: ExtensionContext): string {
  const turns: string[] = []

  for (const entry of ctx.sessionManager.getBranch()) {
    if (entry.type !== 'message') continue
    const message = (entry as { message?: { role?: string; content?: unknown } }).message
    const role = message?.role === 'user' ? 'User' : message?.role === 'assistant' ? 'Assistant' : null

    if (!role) continue
    const content = message.content
    const text = typeof content === 'string'
      ? content
      : Array.isArray(content)
      ? content.filter((p): p is { type: 'text'; text: string } => !!p && typeof p === 'object' && (p as { type?: string }).type === 'text')
        .map((p) => p.text).join('\n')
      : ''
    if (text.trim()) turns.push(`[${role}]: ${text.trim().slice(0, MAX_TURN_TEXT)}`)
  }

  // 首条保底 + 最近若干条，总预算限制
  if (turns.length === 0) return ''
  const opening = turns[0]
  const tail = turns.length > 1 ? turns.slice(1).slice(-RECENT_TURNS) : []
  return [opening, ...tail].join('\n\n').slice(0, MAX_CONVERSATION)
}

export default function(pi: ExtensionAPI) {
  /** 配置实时读取：改 settings.json 后 /reload 或下会话即生效，无需考虑缓存 */
  const maxLen = () => readSettings().autoRename?.maxLen ?? DEFAULT_MAX_LEN

  let named = false
  let inFlight = false

  pi.on('session_start', () => {
    named = false
  })

  /** 首轮 settle 后自动命名（只一次；已有名 / 生成失败则放弃，不重试）
   *
   * 注意：pi 的事件分发对 async handler 是 await 串行等待，若在此处直接
   * await 模型调用（3~8s）会阻塞事件管线；因此悬空执行（void），生成完
   * 成后再异步落盘。代价是 -p 短命进程可能来不及写入即退出（可接受） */
  pi.on('agent_settled', (_event, ctx) => {
    debug('settled: named=', named, 'name=', JSON.stringify(ctx.sessionManager.getSessionName()))
    if (named || inFlight) return
    if (ctx.sessionManager.getSessionName()) return
    const content = firstUserText(ctx)
    debug('firstUserText=', JSON.stringify(content.slice(0, 60)))
    if (!content) return

    named = true
    inFlight = true
    const sessionFile = ctx.sessionManager.getSessionFile()

    void generateTitle(ctx, content, maxLen())
      .then((title) => {
        inFlight = false
        // 生成期间换了 session 或已有名字 → 丢弃，避免改错会话
        if (!title) return
        if (ctx.sessionManager.getSessionFile() !== sessionFile) return
        if (ctx.sessionManager.getSessionName()) return
        try {
          pi.setSessionName(title)
          if (ctx.hasUI) ctx.ui.notify(`Session renamed: ${title}`, 'info')
        }
        catch { /* session 已销毁等：静默 */ }
      })
      .catch(() => {
        inFlight = false
      })
  })

  /** /rename <文字> 直接命名；/rename 无参数按最近对话重新生成 */
  pi.registerCommand('rename', {
    description: 'Rename session; without arguments, generate a title from the recent conversation',
    handler: async (args, ctx) => {
      const direct = args.trim()
      if (direct) {
        pi.setSessionName(direct)
        named = true
        if (ctx.hasUI) ctx.ui.notify(`Session renamed: ${direct}`, 'info')
        return
      }

      const content = recentConversationText(ctx)
      if (!content) {
        if (ctx.hasUI) ctx.ui.notify('No conversation yet; try /rename <title>', 'warning')
        return
      }

      if (ctx.hasUI) ctx.ui.notify('Generating title...', 'info')
      const title = await generateTitle(ctx, content, maxLen())
      if (!title) {
        if (ctx.hasUI) ctx.ui.notify('Failed to generate title', 'warning')
        return
      }

      pi.setSessionName(title)
      named = true
      if (ctx.hasUI) ctx.ui.notify(`Session renamed: ${title}`, 'info')
    },
  })
}
