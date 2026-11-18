// 路线 E 公共函数：由 build.sh 拼进每个场景脚本（run-code 不支持 import）
// 运行环境是 playwright-cli run-code 沙箱：没有 URL / require / process / fs，用到会让会话崩溃
// build.sh 会在本文件前注入 const OUT = '<产物目录>'

/** 当前顶部提示条；新的显示后再销毁旧的，避免闪烁 */
let __hud

/**
 * 在画面顶部显示提示条（只进录屏，pointer-events: none，不影响操作）
 * @param {string} text
 * @param {{ position?: 'top' | 'bottom' }} [opts]
 */
async function hud(page, text, opts = {}) {
  const edge = opts.position === 'bottom' ? 'bottom:10px' : 'top:10px'
  const old = __hud
  __hud = await page.screencast.showOverlay(`<div style="position:absolute;${edge};left:50%;transform:translateX(-50%);padding:8px 14px;background:rgba(17,17,17,.82);color:#fff;border-radius:10px;font:600 13px -apple-system,system-ui,sans-serif;white-space:nowrap">${text}</div>`)
  if (old) await old.dispose()
}

async function hudClear() {
  if (__hud) await __hud.dispose()
  __hud = undefined
}

/** 全屏章节卡，阻塞 duration 毫秒后自动消失 */
async function chapter(page, title, description, duration = 1800) {
  await page.screencast.showChapter(title, { description, duration })
}

/**
 * 录一段视频：自动开始、结束，出错也会停止录制并清掉提示条
 *
 * 视口必须先用 `playwright-cli resize <宽> <高>` 调成与 size 相同，否则画面会留灰边；
 * 在 run-code 里调 page.setViewportSize 不够（实测仍有灰边），所以这里只检查不调整
 * @param {string} name 文件名（不含扩展名），落到 OUT/videos/<name>.webm
 * @param {() => Promise<any>} fn 场景主体，返回值原样返回
 */
async function record(page, name, fn, size = { width: 1440, height: 900 }) {
  const [w, h] = await page.evaluate(() => [innerWidth, innerHeight])
  if (w !== size.width || h !== size.height)
    throw new Error(`视口 ${w}x${h} 与录制尺寸不同，先执行 playwright-cli resize ${size.width} ${size.height}`)
  await page.screencast.start({ path: `${OUT}/videos/${name}.webm`, size })
  try {
    return await fn()
  }
  finally {
    await hudClear().catch(() => {})
    await page.screencast.stop().catch(() => {})
  }
}

/**
 * 安装网络日志：包住 window.fetch，按 match 记录请求，并逐行解析流式响应（SSE）的事件到达时间
 *
 * - 读的是 resp.clone()，业务代码拿到的原始流不受影响
 * - 只覆盖 fetch；XHR、EventSource、WebSocket 记不到
 * - addInitScript 从下一次导航起生效，安装后要 reload 一次
 * - 同一个 context 只装一次（重复调用直接返回）
 * @param {{ match: string }} opts match 是正则源码，匹配请求 URL
 */
async function installNetLog(page, opts) {
  const ctx = page.context()
  if (ctx.__netLogInstalled) return false
  ctx.__netLogInstalled = true

  await ctx.addInitScript((matchSource) => {
    if (window.__netLog) return
    window.__netLog = []
    const re = new RegExp(matchSource)
    const orig = window.fetch.bind(window)

    window.fetch = async (input, init) => {
      const url = typeof input === 'string' ? input : input.url
      if (!re.test(url)) return orig(input, init)
      const entry = {
        method: (init?.method || input.method || 'GET').toUpperCase(),
        url,
        t0: Date.now(),
        reqBody: typeof init?.body === 'string' ? init.body.slice(0, 4000) : null,
        events: [],
        body: '',
      }

      window.__netLog.push(entry)

      try {
        const resp = await orig(input, init)
        entry.status = resp.status
        entry.tHead = Date.now()
        const reader = resp.clone().body?.getReader()

        if (reader) {
          const dec = new TextDecoder()
          let buf = ''
          let eventName

          ;(async () => {
            for (;;) {
              const { done, value } = await reader.read()
              if (done) { entry.tEnd = Date.now(); break }

              const chunk = dec.decode(value, { stream: true })
              if (entry.body.length < 2_000_000) entry.body += chunk

              buf += chunk
              const lines = buf.split('\n')
              buf = lines.pop()

              for (const line of lines) {
                if (line.startsWith('event:')) eventName = line.slice(6).trim()
                else if (line.startsWith('data:')) {
                  let name = eventName
                  try {
                    const j = JSON.parse(line.slice(5).trim())
                    name = j.type ?? j.event ?? name
                  }
                  catch {}
                  entry.events.push({ t: Date.now(), name: name ?? 'message' })
                }
                else if (line === '') eventName = undefined
              }
            }
          })().catch(() => { entry.tEnd = Date.now() })
        }
        return resp
      }
      catch (e) {
        entry.error = String(e)
        entry.tEnd = Date.now()
        throw e
      }
    }
  }, opts.match)
  return true
}

/** 读出 URL 匹配 match（正则源码）的网络日志条目摘要 */
async function netState(page, match) {
  return page.evaluate((m) => {
    const re = new RegExp(m)
    const list = (window.__netLog || []).filter((e) => re.test(e.url))
    const e = list.at(-1)
    return { count: list.length, last: e?.events.at(-1)?.name, ended: !!e?.tEnd, status: e?.status }
  }, match)
}

/**
 * 轮询等待条件成立，期间每秒刷新提示条「label · 已等待 Ns · 最新事件 X」
 *
 * 返回耗时毫秒数，只有约 1s 精度，适合给观众看；报告里的精确数字用 timings()
 * @param {() => Promise<boolean>} pred
 * @param {{ timeout?: number, match?: string }} [opts] match 给出时提示条显示该类请求的最新事件
 */
async function waitFor(page, label, pred, opts = {}) {
  const { timeout = 300_000, match } = opts
  const start = Date.now()
  while (Date.now() - start < timeout) {
    if (await pred()) return Date.now() - start
    const extra = match ? ` · 最新事件 ${(await netState(page, match)).last ?? '—'}` : ''
    await hud(page, `${label} · 已等待 ${Math.round((Date.now() - start) / 1000)}s${extra}`)
    await page.waitForTimeout(1000)
  }
  throw new Error(`timeout: ${label}`)
}

/** 等到 match 类请求比 before 多一条，且最新一条的响应已经结束（流式响应读到末尾） */
async function waitNetDone(page, match, before, label, opts = {}) {
  return waitFor(page, label, async () => {
    const s = await netState(page, match)
    return s.count > before && s.ended
  }, { ...opts, match })
}

/** 逐字输入，录屏里能看到打字过程 */
async function typeSlowly(locator, text, delay = 40) {
  await locator.click()
  await locator.pressSequentially(text, { delay })
}

/** 隐藏开发浮层、调试按钮等不该进录屏的元素 */
async function hideSelectors(page, selectors) {
  await page.addStyleTag({ content: `${selectors.join(',')}{display:none !important}` })
}

/**
 * 整理网络日志为耗时表（毫秒，相对请求发出时刻）
 *
 * - headersMs：收到响应头
 * - firstMs：每种事件第一次到达
 * - endMs：响应读完
 */
async function timings(page, match) {
  return page.evaluate((m) => {
    const re = new RegExp(m)
    return (window.__netLog || []).filter((e) => re.test(e.url)).map((e) => {
      const rel = (t) => (t ? t - e.t0 : null)
      const firstMs = {}
      for (const ev of e.events) if (!(ev.name in firstMs)) firstMs[ev.name] = rel(ev.t)
      return {
        method: e.method,
        url: e.url.replace(location.origin, ''),
        status: e.status,
        at: new Date(e.t0).toISOString(),
        headersMs: rel(e.tHead),
        firstMs,
        endMs: rel(e.tEnd),
        error: e.error,
      }
    })
  }, match)
}
