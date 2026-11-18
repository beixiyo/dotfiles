/**
 * 通用网页录制：把任意页面（或其中一个元素）录成 GIF / MP4
 *
 * 三种停止方式（--stop）：
 * - duration:<秒>   固定时长，适合自动播放的动画
 * - loop:<属性名>   页面每轮开始把该属性 +1，录「第 N 轮开始 → 第 N+1 轮开始」，得到无缝循环
 * - scenario        跑完 --scenario 脚本即停止（脚本里用 Playwright 操作真实应用），默认值
 *
 * 流程：Playwright 打开页面 → CDP Page.startScreencast 逐帧落盘（带真实时间戳）
 *      → ffmpeg concat 按每帧真实时长拼接 → 裁剪 → GIF 两段式调色板 / MP4 H.264
 *
 * 用法：bun run record.ts --url <url> [选项]   （Node ≥ 22.18 也可直接 node record.ts）
 * 依赖：目标项目或全局可解析的 playwright / @playwright/test（含 chromium），PATH 中的 ffmpeg / ffprobe
 * 选项见文件底部 HELP
 */
import { type ChildProcess, execFile, spawn } from 'node:child_process'
import { existsSync } from 'node:fs'
import { mkdir, mkdtemp, rm, stat, writeFile } from 'node:fs/promises'
import { createRequire } from 'node:module'
import { tmpdir } from 'node:os'
import { dirname, join, resolve } from 'node:path'
import { pathToFileURL } from 'node:url'
import { parseArgs, promisify } from 'node:util'

const run = promisify(execFile)

/** 元素裁剪时四周保留的留白（CSS px），让圆角与阴影不被切掉 */
const CROP_PAD = 12
const SERVER_READY_TIMEOUT_MS = 90_000
const MP4_MAX_FPS = 60
/** 静止自检：冻结时长占比达到该值视为「几乎没动」 */
const MOTION_MIN_FROZEN_RATIO = 0.95
/**
 * 静止自检：首尾帧变化像素占比低于该值视为「没留下结果」
 * 实测（1280×800 视口）：仅光标闪烁 0.002%，输入 "Hello world" 0.048%，取 0.01% 两边各留约 5 倍余量
 */
const MOTION_MIN_END_CHANGE = 0.0001
/** freezedetect 噪声阈值（帧间平均差异比例），低于它视为没变；光标闪烁约在此量级之下 */
const FREEZE_NOISE = 0.003
/** freezedetect 最短冻结时长（秒），短于它的停顿不计 */
const FREEZE_MIN_SECONDS = 0.5

async function main() {
  const opts = parseOptions(process.argv.slice(2))
  if (!opts) {
    console.log(HELP)
    return
  }
  await assertFfmpeg()
  const { chromium } = await loadPlaywright()

  const server = await ensureServer(opts.url, opts.serve)
  const workDir = await mkdtemp(join(tmpdir(), 'record-'))
  const browser = await chromium.launch()
  try {
    const context = await browser.newContext({
      viewport: opts.viewport,
      deviceScaleFactor: opts.dpr,
      colorScheme: opts.colorScheme,
      locale: opts.locale,
      reducedMotion: 'no-preference',
    })
    const page = await context.newPage()
    const capture = await captureSegment(page, opts, workDir)

    const listPath = join(workDir, 'frames.txt')
    await writeFile(listPath, capture.concatList)
    // 静止自检只警告不报错：启发式判断可能误判，成片照常产出
    const motionWarning = await checkMotion(listPath, capture)
    await mkdir(dirname(opts.out), { recursive: true })

    if (opts.formats.includes('gif')) {
      const path = `${opts.out}.gif`
      await encodeGif({ listPath, crop: capture.crop, outPath: path, width: opts.width, fps: opts.fps, colors: opts.colors })
      await report(path)
    }
    if (opts.formats.includes('mp4')) {
      const path = `${opts.out}.mp4`
      await encodeMp4({ listPath, crop: capture.crop, outPath: path, width: opts.mp4Width, fps: capture.captureFps })
      await report(path)
    }
    if (motionWarning) console.warn(`\n⚠ record: ${motionWarning}`)
  }
  finally {
    await browser.close()
    await rm(workDir, { recursive: true, force: true })
    server.stop()
  }
}

/**
 * 抓取一段帧：按停止方式确定 [start, end) 区间，返回 concat 列表与裁剪区域（图像像素）
 * 时间轴统一用 epoch 秒：screencast 的 metadata.timestamp 与页面 timeOrigin + now() 都源自系统时钟
 */
async function captureSegment(page: Page, opts: Options, workDir: string): Promise<Capture> {
  const pageErrors: string[] = []
  page.on('pageerror', (err: Error) => pageErrors.push(err.message))

  // 循环模式：观察整页（subtree），元素被重建或热更新时也不丢边界；只接受恰好 +1 的变化
  const loopEvents: number[] = []
  let onLoop: (() => void) | null = null
  if (opts.stop.kind === 'loop') {
    await page.exposeBinding('__recordLoop', (_src: unknown, at: number) => {
      loopEvents.push(at)
      onLoop?.()
    })
  }

  await page.goto(opts.url, { waitUntil: 'load' })
  if (opts.waitFor) {
    await page.locator(opts.waitFor).first().waitFor({ state: 'visible', timeout: 20_000 }).catch(() => {
      const detail = pageErrors.length ? `\nPage errors:\n${pageErrors.join('\n')}` : ''
      throw new Error(`Timed out waiting for ${opts.waitFor} on ${opts.url}${detail}`)
    })
  }
  await page.evaluate(() => document.fonts.ready.then(() => undefined))
  if (opts.selector) await fitViewportToElement(page, opts.selector)

  if (opts.stop.kind === 'loop') {
    await page.evaluate((attr: string) => {
      let last = Number.NaN
      const read = () => {
        const el = document.querySelector(`[${attr}]`)
        const value = el ? Number(el.getAttribute(attr)) : Number.NaN
        if (!Number.isNaN(value) && value === last + 1) {
          ;(window as unknown as { __recordLoop: (at: number) => void }).__recordLoop((performance.timeOrigin + performance.now()) / 1000)
        }
        if (!Number.isNaN(value)) last = value
      }
      read()
      new MutationObserver(read).observe(document.documentElement, { subtree: true, childList: true, attributes: true, attributeFilter: [attr] })
    }, opts.stop.attr)
  }

  // 抓帧：每帧立即 ack，写盘异步进行，最后统一等待
  const cdp = await page.context().newCDPSession(page)
  const frames: Frame[] = []
  const writes: Promise<void>[] = []
  cdp.on('Page.screencastFrame', ({ data, metadata, sessionId }: ScreencastFrame) => {
    void cdp.send('Page.screencastFrameAck', { sessionId }).catch(() => {})
    const path = join(workDir, `f${String(frames.length).padStart(6, '0')}.jpg`)
    frames.push({ path, at: metadata.timestamp ?? Date.now() / 1000 })
    writes.push(writeFile(path, data, 'base64'))
  })

  const vp = page.viewportSize()!
  await cdp.send('Page.startScreencast', {
    format: 'jpeg',
    quality: 95,
    everyNthFrame: 1,
    maxWidth: vp.width * opts.dpr,
    maxHeight: vp.height * opts.dpr,
  })

  let start = 0
  let end = 0
  try {
    if (opts.stop.kind === 'duration') {
      start = Date.now() / 1000
      await page.waitForTimeout(opts.stop.seconds * 1000)
      end = Date.now() / 1000
    }
    else if (opts.stop.kind === 'loop') {
      const waitCount = (count: number, label: string) =>
        new Promise<void>((done, fail) => {
          if (loopEvents.length >= count) return done()
          const timer = setTimeout(() => fail(new Error(`${label}: loop attribute did not increment within ${opts.loopTimeout}s`)), opts.loopTimeout * 1000)
          onLoop = () => {
            if (loopEvents.length < count) return
            clearTimeout(timer)
            done()
          }
        })
      // 首个边界之前的循环不完整，从第 1 个边界录到第 2 个边界
      await waitCount(1, 'Waiting for loop start')
      await waitCount(2, 'Waiting for loop end')
      start = loopEvents[0]
      end = loopEvents[1]
    }
    else {
      const scenario = await loadScenario(opts.scenario!)
      // 场景开始前留一点静止画面，结尾停留 tail 毫秒让最终状态被看清
      await page.waitForTimeout(opts.head)
      start = Date.now() / 1000 - opts.head / 1000
      await scenario({ page })
      await page.waitForTimeout(opts.tail)
      end = Date.now() / 1000
    }
  }
  finally {
    onLoop = null
    await cdp.send('Page.stopScreencast').catch(() => {})
  }
  await Promise.all(writes)

  const segment = sliceSegment(frames, start, end)
  const frameSize = await probeSize(segment.firstPath)
  const scale = frameSize.width / vp.width
  const rect = opts.selector
    ? await page.locator(opts.selector).first().evaluate((el: Element, pad: number) => {
      const r = el.getBoundingClientRect()
      return { x: r.x - pad, y: r.y - pad, width: r.width + pad * 2, height: r.height + pad * 2 }
    }, CROP_PAD)
    : { x: 0, y: 0, width: vp.width, height: vp.height }

  return {
    concatList: segment.list,
    crop: toEvenCrop({ x: rect.x * scale, y: rect.y * scale, width: rect.width * scale, height: rect.height * scale }, frameSize),
    captureFps: segment.fps,
    frameCount: segment.count,
    duration: end - start,
    firstFrame: segment.firstPath,
    lastFrame: segment.lastPath,
    loop: opts.stop.kind === 'loop',
  }
}

/**
 * 目标元素超出视口时把视口撑到能容纳它（含留白），避免被截断
 * 只按元素撑开，不按整页：整页过高时 screencast 会缩小输出，反而降低清晰度
 */
async function fitViewportToElement(page: Page, selector: string) {
  const box = await page.locator(selector).first().evaluate((el: Element, pad: number) => {
    const r = el.getBoundingClientRect()
    return { right: r.right + pad, bottom: r.bottom + pad }
  }, CROP_PAD)
  const vp = page.viewportSize()!
  if (box.right > vp.width || box.bottom > vp.height) {
    await page.setViewportSize({ width: Math.ceil(Math.max(vp.width, box.right)), height: Math.ceil(Math.max(vp.height, box.bottom)) })
  }
}

/**
 * 截取 [start, end) 区间的帧，生成 concat-demuxer 列表
 * screencast 只在画面变化时出帧：起点画面取 start 之前最后一帧，每帧 duration = 到下一帧的间隔，末帧延续到 end
 */
function sliceSegment(frames: Frame[], start: number, end: number) {
  if (frames.length === 0) throw new Error('No frames captured; screencast may not be working')
  let first = 0
  for (let i = 0; i < frames.length; i++) {
    if (frames[i].at <= start) first = i
    else break
  }
  const picked = frames.slice(first).filter((frame, i) => i === 0 || frame.at < end)

  const lines: string[] = []
  const intervals: number[] = []
  for (let i = 0; i < picked.length; i++) {
    const from = i === 0 ? start : picked[i].at
    const to = i + 1 < picked.length ? picked[i + 1].at : end
    const duration = Math.max(to - from, 0.001)
    if (i > 0 && i + 1 < picked.length) intervals.push(duration)
    lines.push(`file '${picked[i].path}'`, `duration ${duration.toFixed(6)}`)
  }
  // concat demuxer 忽略最后一条 duration，重复末帧使其生效
  lines.push(`file '${picked[picked.length - 1].path}'`)

  // 采集帧率：帧间隔中位数（运动段帧最密），上限 60
  intervals.sort((a, b) => a - b)
  const median = intervals[Math.floor(intervals.length / 2)] ?? 1 / 30
  const fps = Math.min(MP4_MAX_FPS, Math.max(1, Math.round(1 / median)))
  return { list: `${lines.join('\n')}\n`, fps, firstPath: picked[0].path, lastPath: picked[picked.length - 1].path, count: picked.length }
}

/**
 * 静止自检：录制区域几乎没变，大概率是场景选择器/坐标没命中、页面没渲染或 screencast 未工作
 * 三个信号：
 * 1. 帧数：screencast 只在画面变化时出帧，区间内 ≤ 2 帧即确定静止
 * 2. 冻结占比：ffmpeg freezedetect 统计裁剪区域冻结时长；光标闪烁、逐字输入这类小面积变化都低于噪声阈值
 * 3. 首尾差异：首帧与末帧之间变化像素的占比，区分「只有光标在闪」（首尾相同）与「输入了文字」（首尾不同）
 * 判定：冻结占比 ≥ 阈值，且（循环录制 或 首尾差异 < 阈值）→ 静止。循环录制首尾按设计相同，只看冻结占比
 * 返回警告文案，未发现问题返回 null；只用于提示，不阻断产出
 */
async function checkMotion(listPath: string, capture: Capture): Promise<string | null> {
  const hint = 'Check a few frames. Common causes: scenario selectors or coordinates missed, page not rendered yet, wrong recording area (--selector)'
  if (capture.frameCount <= 2) {
    return `Nothing changed during the ${capture.duration.toFixed(1)}s recording (only ${capture.frameCount} frame(s)). ${hint}`
  }

  const frozenRatio = await measureFrozenRatio(listPath, capture)
  const endChange = capture.loop ? 0 : await measureEndChange(capture)
  if (process.env.RECORD_DEBUG) {
    console.log(`record: motion check frames=${capture.frameCount} frozen=${(frozenRatio * 100).toFixed(1)}% endChange=${(endChange * 100).toFixed(3)}%`)
  }

  const staticByEnds = capture.loop || endChange < MOTION_MIN_END_CHANGE
  if (frozenRatio >= MOTION_MIN_FROZEN_RATIO && staticByEnds) {
    return `The frame was static for ${(frozenRatio * 100).toFixed(0)}% of the ${capture.duration.toFixed(1)}s recording, and the first and last frames are nearly identical. ${hint}`
  }
  return null
}

/** 裁剪区域的冻结时长占比（0–1）；缩到 320px 宽做 freezedetect，开销很小 */
async function measureFrozenRatio(listPath: string, capture: Capture) {
  const { crop } = capture
  const { stderr } = await run('ffmpeg', [
    '-hide_banner', '-nostats', '-f', 'concat', '-safe', '0', '-i', listPath,
    '-vf', `crop=${crop.width}:${crop.height}:${crop.x}:${crop.y},scale=320:-2,freezedetect=n=${FREEZE_NOISE}:d=${FREEZE_MIN_SECONDS}`,
    '-an', '-f', 'null', '-',
  ], { maxBuffer: 64 * 1024 * 1024 })

  // freezedetect 输出 freeze_start / freeze_end；冻结持续到结尾时没有 end，按区间终点计
  let frozen = 0
  let openStart: number | null = null
  for (const match of stderr.matchAll(/lavfi\.freezedetect\.freeze_(start|end): ([\d.]+)/g)) {
    const at = Number(match[2])
    if (match[1] === 'start') openStart = at
    else if (openStart !== null) {
      frozen += at - openStart
      openStart = null
    }
  }
  if (openStart !== null) frozen += capture.duration - openStart
  return capture.duration > 0 ? Math.min(1, frozen / capture.duration) : 1
}

/**
 * 首帧与末帧在裁剪区域内的变化像素占比（0–1）
 * 两帧求差转灰度后二值化（差值 > 24 记 255，吸收 JPEG 重压缩噪声），signalstats 的平均亮度 / 255 即变化占比
 * 不用 blackframe：它的 pblack 只有整数百分比，小面积变化（输入几个字）分辨不出
 */
async function measureEndChange(capture: Capture) {
  const { crop } = capture
  const c = `crop=${crop.width}:${crop.height}:${crop.x}:${crop.y}`
  const { stderr } = await run('ffmpeg', [
    '-hide_banner', '-nostats', '-i', capture.firstFrame, '-i', capture.lastFrame,
    '-lavfi', `[0]${c},format=yuv444p[a];[1]${c},format=yuv444p[b];[a][b]blend=all_mode=difference,format=gray,lut=y='if(gt(val,24),255,0)',signalstats,metadata=mode=print:key=lavfi.signalstats.YAVG`,
    '-frames:v', '1', '-f', 'null', '-',
  ], { maxBuffer: 16 * 1024 * 1024 })
  const yavg = Number(/lavfi\.signalstats\.YAVG=([\d.]+)/.exec(stderr)?.[1] ?? 0)
  return Math.min(1, yavg / 255)
}

/**
 * GIF：裁剪 → 定帧率 → lanczos 缩放 → split 两段式调色板，不抖动
 * 平涂 UI 不抖动最小最清晰；diff_mode=rectangle 只重绘变化区域。整幅运动（镜头推拉、滚动）是体积主因，优先降帧率
 */
async function encodeGif(params: { listPath: string; crop: Crop; outPath: string; width: number; fps: number; colors: number }) {
  const { listPath, crop, outPath, width, fps, colors } = params
  const filter = [
    `[0:v]crop=${crop.width}:${crop.height}:${crop.x}:${crop.y},fps=${fps},scale=${width}:-1:flags=lanczos,split[a][b]`,
    `[a]palettegen=stats_mode=diff:max_colors=${colors}[p]`,
    '[b][p]paletteuse=dither=none:diff_mode=rectangle',
  ].join(';')
  await ffmpeg(['-f', 'concat', '-safe', '0', '-i', listPath, '-filter_complex', filter, '-loop', '0', outPath])
}

/** MP4：H.264 yuv420p 偶数尺寸，faststart 便于网页内播放 */
async function encodeMp4(params: { listPath: string; crop: Crop; outPath: string; width: number; fps: number }) {
  const { listPath, crop, outPath, width, fps } = params
  const filter = `crop=${crop.width}:${crop.height}:${crop.x}:${crop.y},fps=${fps},scale=${width}:-2:flags=lanczos,format=yuv420p`
  await ffmpeg([
    '-f',
    'concat',
    '-safe',
    '0',
    '-i',
    listPath,
    '-vf',
    filter,
    '-c:v',
    'libx264',
    '-preset',
    'slow',
    '-crf',
    '20',
    '-pix_fmt',
    'yuv420p',
    '-movflags',
    '+faststart',
    '-an',
    outPath,
  ])
}

/**
 * 确保页面可访问：已在运行则复用；不可访问且提供了 --serve 时启动该命令，返回的 stop 只结束自己启动的进程组
 */
async function ensureServer(url: string, serve: string | undefined): Promise<{ stop: () => void }> {
  if (url.startsWith('file:') || (await isReachable(url))) return { stop: () => {} }
  if (!serve) throw new Error(`Cannot reach ${url}; start the server yourself, or pass --serve "<command>" to let the script start it`)

  console.log(`record: ${url} is not running, running: ${serve}`)
  const child = spawn(serve, { shell: true, detached: true, stdio: ['ignore', 'ignore', 'pipe'] })
  const stderr: string[] = []
  child.stderr?.on('data', (chunk: Buffer) => stderr.push(chunk.toString()))
  const stop = () => killGroup(child)
  try {
    const deadline = Date.now() + SERVER_READY_TIMEOUT_MS
    while (!(await isReachable(url))) {
      if (child.exitCode !== null) {
        throw new Error(`Serve command exited with code ${child.exitCode}:\n${stderr.join('').trim().split('\n').slice(-5).join('\n')}`)
      }
      if (Date.now() > deadline) throw new Error(`${url} not ready within ${SERVER_READY_TIMEOUT_MS / 1000}s`)
      await new Promise((done) => setTimeout(done, 300))
    }
  }
  catch (err) {
    stop()
    throw err
  }
  return { stop }
}

async function isReachable(url: string) {
  try {
    await fetch(url, { signal: AbortSignal.timeout(1500) })
    return true
  }
  catch {
    return false
  }
}

/** 结束自动启动的进程组（shell → pnpm → vite），避免残留 */
function killGroup(child: ChildProcess) {
  if (child.pid === undefined || child.exitCode !== null) return
  try {
    process.kill(-child.pid, 'SIGTERM')
  }
  catch {
    child.kill('SIGTERM')
  }
}

/** 从当前目录向上解析 playwright / @playwright/test，找不到时给出安装提示 */
async function loadPlaywright(): Promise<{ chromium: Chromium }> {
  const require = createRequire(join(process.cwd(), 'noop.js'))
  for (const name of ['playwright', '@playwright/test', 'playwright-core']) {
    try {
      const mod = await import(pathToFileURL(require.resolve(name)).href)
      const chromium = (mod.chromium ?? mod.default?.chromium) as Chromium | undefined
      if (chromium) return { chromium }
    }
    catch {
      // 继续尝试下一个包名
    }
  }
  throw new Error(
    'Cannot resolve playwright from the current directory; run inside the target project, or install it first: pnpm add -D playwright && pnpm exec playwright install chromium',
  )
}

/** 加载场景脚本：默认导出 async ({ page }) => void */
async function loadScenario(path: string): Promise<Scenario> {
  const abs = resolve(path)
  if (!existsSync(abs)) throw new Error(`Scenario script not found: ${abs}`)
  const mod = await import(pathToFileURL(abs).href)
  const fn = (mod.default ?? mod.scenario) as Scenario | undefined
  if (typeof fn !== 'function') throw new Error(`Scenario script must default-export async ({ page }) => void: ${abs}`)
  return fn
}

async function ffmpeg(args: string[]) {
  try {
    await run('ffmpeg', ['-y', '-hide_banner', '-loglevel', 'error', ...args], { maxBuffer: 64 * 1024 * 1024 })
  }
  catch (err) {
    const stderr = (err as { stderr?: string }).stderr ?? ''
    throw new Error(`ffmpeg failed:\n${stderr.trim().split('\n').slice(-5).join('\n') || String(err)}`)
  }
}

async function report(path: string) {
  const { stdout } = await run('ffprobe', [
    '-v',
    'error',
    '-select_streams',
    'v:0',
    '-show_entries',
    'format=duration:stream=width,height',
    '-of',
    'json',
    path,
  ])
  const info = JSON.parse(stdout) as { format: { duration?: string }; streams: { width?: number; height?: number }[] }
  const s = info.streams[0] ?? {}
  const { size } = await stat(path)
  console.log(`${path}  ${Number(info.format.duration ?? 0).toFixed(2)}s  ${s.width}x${s.height}  ${(size / 1024 / 1024).toFixed(2)} MB`)
}

/** 读取图像尺寸（px） */
async function probeSize(path: string) {
  const { stdout } = await run('ffprobe', ['-v', 'error', '-show_entries', 'stream=width,height', '-of', 'csv=p=0', path])
  const [width, height] = stdout.trim().split(',').map(Number)
  if (!width || !height) throw new Error(`Cannot read frame size: ${path}`)
  return { width, height }
}

async function assertFfmpeg() {
  for (const bin of ['ffmpeg', 'ffprobe']) {
    await run(bin, ['-version']).catch(() => {
      throw new Error(`${bin} not found; install it first (macOS: brew install ffmpeg)`)
    })
  }
}

/** 裁剪区域取整到偶数像素（yuv420p 要求），并钳制在帧范围内（元素部分在视口外时不越界） */
function toEvenCrop(c: Crop, frame: { width: number; height: number }): Crop {
  const even = (n: number) => Math.max(0, Math.floor(n / 2) * 2)
  const x = even(Math.min(Math.max(0, c.x), frame.width - 2))
  const y = even(Math.min(Math.max(0, c.y), frame.height - 2))
  return { x, y, width: even(Math.min(c.width, frame.width - x)), height: even(Math.min(c.height, frame.height - y)) }
}

/** 命令行选项定义；默认值即公共契约，与 HELP 保持一致 */
const CLI_OPTIONS = {
  url: { type: 'string' },
  stop: { type: 'string' },
  scenario: { type: 'string' },
  head: { type: 'string', default: '400' },
  tail: { type: 'string', default: '1200' },
  serve: { type: 'string' },
  selector: { type: 'string' },
  'wait-for': { type: 'string' },
  viewport: { type: 'string', default: '1280x800' },
  dpr: { type: 'string', default: '2' },
  'color-scheme': { type: 'string', default: 'light' },
  locale: { type: 'string' },
  'loop-timeout': { type: 'string', default: '60' },
  out: { type: 'string', default: 'recording' },
  format: { type: 'string', default: 'gif' },
  width: { type: 'string', default: '720' },
  fps: { type: 'string', default: '12' },
  colors: { type: 'string', default: '128' },
  'mp4-width': { type: 'string', default: '1280' },
  help: { type: 'boolean', short: 'h' },
} as const

/** 按 CLI_OPTIONS 解析参数（strict：未知选项、缺值直接报错），错误信息附带用法 */
function readCli(argv: string[]) {
  try {
    return parseArgs({ args: argv, options: CLI_OPTIONS, strict: true }).values
  }
  catch (err) {
    throw new Error(`${err instanceof Error ? err.message : String(err)}\n\n${HELP}`)
  }
}

/** 解析并校验命令行，归一化为 Options；--help 时返回 null */
function parseOptions(argv: string[]): Options | null {
  const values = readCli(argv)
  if (values.help) return null

  const num = (name: keyof typeof CLI_OPTIONS, min = 1) => {
    const raw = values[name] as string
    const value = Number(raw)
    if (!Number.isFinite(value) || value < min) throw new Error(`--${name} expects a number >= ${min}, got ${raw}`)
    return value
  }

  const { url, scenario } = values
  if (!url) throw new Error(`Missing --url\n\n${HELP}`)

  const stopRaw = values.stop ?? (scenario ? 'scenario' : '')
  let stop: Stop
  if (stopRaw.startsWith('duration:')) {
    const seconds = Number(stopRaw.slice(9))
    if (!(seconds > 0)) throw new Error(`--stop duration:<seconds> expects a positive number, got ${stopRaw}`)
    stop = { kind: 'duration', seconds }
  }
  else if (stopRaw.startsWith('loop:')) stop = { kind: 'loop', attr: stopRaw.slice(5) }
  else if (stopRaw === 'scenario') stop = { kind: 'scenario' }
  else throw new Error('Need --stop duration:<seconds> | loop:<attr>, or provide --scenario <file>')
  if (stop.kind === 'scenario' && !scenario) throw new Error('--stop scenario requires --scenario <file>')
  if (stop.kind === 'loop' && !/^[\w-]+$/.test(stop.attr)) throw new Error(`Invalid loop attribute name: ${stop.attr}`)

  const [vw, vh] = values.viewport.split('x').map(Number)
  if (!vw || !vh) throw new Error('--viewport expects <width>x<height>, e.g. 1280x800')
  const formats = values.format.split(',').filter((f): f is Format => f === 'gif' || f === 'mp4')
  if (formats.length === 0) throw new Error('--format only accepts gif, mp4, or gif,mp4')
  const colorScheme = values['color-scheme']
  if (colorScheme !== 'light' && colorScheme !== 'dark') throw new Error('--color-scheme only accepts light | dark')

  return {
    url,
    serve: values.serve,
    selector: values.selector,
    waitFor: values['wait-for'] ?? values.selector,
    stop,
    scenario,
    head: num('head', 0),
    tail: num('tail', 0),
    loopTimeout: num('loop-timeout'),
    viewport: { width: vw, height: vh },
    dpr: num('dpr'),
    colorScheme,
    locale: values.locale,
    out: resolve(values.out),
    formats,
    width: num('width'),
    fps: num('fps'),
    colors: Math.min(256, num('colors', 2)),
    mp4Width: Math.round(num('mp4-width') / 2) * 2,
  }
}

const HELP = `Usage: bun run record.ts --url <url> [options]

Stop conditions (choose one)
  --stop duration:<seconds>  Record for a fixed duration
  --stop loop:<attr>         Page increments this attribute once per loop; records one full seamless loop
  --scenario <file.ts>       Stop after the scenario script finishes; default-export async ({ page }) => void
    --head <ms>              Still frames before the scenario, default 400
    --tail <ms>              Hold frames after the scenario, default 1200

Page
  --serve "<command>"        If the url is unreachable, run this command to start the server; its process group is stopped when done
  --selector <css>           Record only this element (with ${CROP_PAD}px padding), default: whole viewport; also the default for --wait-for
  --wait-for <css>           Wait for this element to become visible before recording
  --viewport 1280x800        Viewport, default 1280x800 (auto-expanded if content is larger)
  --dpr 2                    Device pixel ratio, default 2 (sharper text)
  --color-scheme light|dark  Default light
  --locale zh-CN             Browser locale
  --loop-timeout 60          Seconds to wait for each loop boundary in loop mode

Output
  --out <path>               Output path without extension (.gif/.mp4 is appended), default ./recording
  --format gif|mp4|gif,mp4   Default gif
  --width 720 --fps 12 --colors 128   GIF options (prefer lowering fps when the whole frame moves)
  --mp4-width 1280           MP4 width

Self-check
  Warns at the end (output is still written) when the recorded area stays almost static,
  a typical sign of missed selectors or an unrendered page. RECORD_DEBUG=1 prints the metrics`

type Format = 'gif' | 'mp4'

type Stop =
  | { kind: 'duration'; seconds: number }
  | { kind: 'loop'; attr: string }
  | { kind: 'scenario' }

interface Options {
  url: string
  /** url 不可访问时的启动命令 */
  serve?: string
  /** 裁剪目标元素；缺省录整个视口 */
  selector?: string
  waitFor?: string
  stop: Stop
  scenario?: string
  /** @default 400 */
  head: number
  /** @default 1200 */
  tail: number
  /** @default 60 */
  loopTimeout: number
  /** @default { width: 1280, height: 800 } */
  viewport: { width: number; height: number }
  /** @default 2 */
  dpr: number
  /** @default 'light' */
  colorScheme: 'light' | 'dark'
  locale?: string
  /** 输出路径（不含扩展名） @default './recording' */
  out: string
  /** @default ['gif'] */
  formats: Format[]
  /** GIF 宽度 @default 720 */
  width: number
  /** GIF 帧率 @default 12 */
  fps: number
  /** GIF 调色板颜色数 @default 128 */
  colors: number
  /** @default 1280 */
  mp4Width: number
}

interface Frame {
  path: string
  /** epoch 秒 */
  at: number
}

interface Crop {
  x: number
  y: number
  width: number
  height: number
}

interface Capture {
  concatList: string
  crop: Crop
  captureFps: number
  /** 区间内的去重帧数（screencast 只在画面变化时出帧） */
  frameCount: number
  /** 区间时长（秒） */
  duration: number
  firstFrame: string
  lastFrame: string
  /** 循环录制：首尾帧按设计相同，不能用首尾差异判断 */
  loop: boolean
}

interface ScreencastFrame {
  data: string
  sessionId: number
  metadata: { timestamp?: number }
}

/** 场景脚本签名 */
type Scenario = (ctx: { page: Page }) => Promise<void>

/** 只声明用到的 Playwright 能力，脚本不强依赖类型包 */
interface Chromium {
  launch(): Promise<{ newContext(options: Record<string, unknown>): Promise<{ newPage(): Promise<Page> }>; close(): Promise<void> }>
}

interface Page {
  on(event: 'pageerror', handler: (err: Error) => void): void
  goto(url: string, options?: Record<string, unknown>): Promise<unknown>
  locator(selector: string): { first(): Locator }
  evaluate<R, A = undefined>(fn: (arg: A) => R | Promise<R>, arg?: A): Promise<R>
  exposeBinding(name: string, fn: (...args: never[]) => unknown): Promise<void>
  waitForTimeout(ms: number): Promise<void>
  viewportSize(): { width: number; height: number } | null
  setViewportSize(size: { width: number; height: number }): Promise<void>
  context(): { newCDPSession(page: Page): Promise<CDPSession> }
}

interface Locator {
  waitFor(options: Record<string, unknown>): Promise<void>
  evaluate<R, A>(fn: (el: Element, arg: A) => R, arg: A): Promise<R>
}

interface CDPSession {
  on(event: 'Page.screencastFrame', handler: (frame: ScreencastFrame) => void): void
  send(method: string, params?: Record<string, unknown>): Promise<unknown>
}

// 入口放在文件末尾：所有模块级常量（CLI_OPTIONS、HELP）初始化后才执行，避免 TDZ
main().catch((err: unknown) => {
  console.error(`record: ${err instanceof Error ? err.message : String(err)}`)
  process.exitCode = 1
})
