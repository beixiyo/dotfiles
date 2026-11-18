# Electron 实验脚本骨架

以下来自 macOS 窗口实验，具体系统和 Electron 版本未记录。作为按需改写的示例，先核实当前 API、目标应用、窗口配置和权限；固定坐标、延迟、层级及窗口选择条件不是通用默认值

放在 scratchpad 目录，用项目自己的 Electron 跑：

```bash
cd <project>   # 让 node_modules/.bin/electron 与业务同版本
OUT_DIR=/path/to/lab MATERIALS=popover,hud,under-window ./node_modules/.bin/electron /path/to/lab/main.js
```

## 参数扫描 + 区域截图

```js
/* main.js：在目标 App 窗口上方开一个与业务窗口同配置的窗口，逐参数截图 */
const { app, BrowserWindow, nativeTheme, shell } = require('electron')
const { execFileSync } = require('node:child_process')
const path = require('node:path')

const OUT = process.env.OUT_DIR
const MATERIALS = (process.env.MATERIALS || 'popover').split(',')
const STATE = process.env.VISUAL_STATE || 'active'
const sleep = ms => new Promise(r => setTimeout(r, ms))

app.whenReady().then(async () => {
  nativeTheme.themeSource = process.env.THEME_SOURCE || 'system'

  /** 先把背景 App 拉到前面，再定位它的窗口 */
  shell.openExternal('x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility')
  await sleep(2500)
  const target = JSON.parse(execFileSync(process.env.WINDOW_HELPER).toString())
  if (!target.found) { app.quit(); return }

  const W = 539, H = 147
  const x = Math.round(target.x + (target.width - W) / 2)
  const y = Math.round(target.y + target.height - H - 44)

  const win = new BrowserWindow({
    width: W, height: H, x, y,
    frame: false, transparent: true, backgroundColor: '#00000000',
    vibrancy: MATERIALS[0], visualEffectState: STATE,
    alwaysOnTop: true, focusable: false, hasShadow: true, type: 'panel', show: false,
    webPreferences: { sandbox: true },
  })
  win.setAlwaysOnTop(true, 'floating')
  if (process.env.OPACITY) win.setOpacity(Number(process.env.OPACITY))

  await win.loadURL('data:text/html;charset=utf-8,' + encodeURIComponent(
    '<body style="margin:0;background:transparent;font:16px -apple-system"><div id="l" style="padding:24px"></div></body>',
  ))
  win.showInactive()

  for (const m of MATERIALS) {
    win.setVibrancy(m)
    await win.webContents.executeJavaScript(`document.getElementById('l').textContent = ${JSON.stringify(m)}`)
    await sleep(700)
    /** 取景固定：窗口矩形向外扩 30，所有样本同一取景 */
    execFileSync('screencapture', ['-x', '-R', `${x - 30},${y - 30},${W + 60},${H + 60}`, path.join(OUT, `${STATE}-${m}.png`)])
  }
  win.destroy()
  app.quit()
})
```

## 渲染业务的真实构建产物

需要隔离后端时，可用显式假 IPC 渲染业务产物。优先保留业务安全配置并提供所需接口；下例宽泛 Proxy 与关闭隔离仅限受控本地实验，不移入业务配置，也不加载外部内容。mock 可能掩盖缺失调用，不能证明真实 IPC 或业务流程正常

```js
/* 此示例直接写主世界 globalThis，因此使用 contextIsolation: false；不要据此推断其他 mock 也需要关闭隔离 */
const swallow = new Proxy(function () {}, {
  get: (_t, k) => (k === 'then' ? undefined : swallow),
  apply: () => swallow,
})
const payload = { /* 组件需要的数据 */ }
globalThis.$ipc = new Proxy({}, {
  get: (_t, ns) => ns === 'permission'
    ? { on: () => () => {}, getDragGuideState: async () => payload }
    : swallow,
})
```

```js
const win = new BrowserWindow({
  /* 同上 */
  webPreferences: { preload: path.join(__dirname, 'preload-mock.js'), contextIsolation: false, sandbox: false, nodeIntegration: false },
})
win.webContents.on('console-message', (_e, level, message) => { if (level >= 2) console.log('console:', message) })
await win.loadFile(process.env.GUIDE_HTML)   // out/renderer/windows/<name>/index.html
/** 验证组件自己做了什么，而不是实验脚本替它做的 */
console.log(await win.webContents.executeJavaScript('document.documentElement.className'))
```

## 定位别的进程的窗口（Swift）

先检查当前权限下能读到哪些字段；缺字段或查不到窗口不直接等于进程没有窗口

```swift
import Cocoa
import CoreGraphics

let pids = NSWorkspace.shared.runningApplications
  .filter { $0.bundleIdentifier == "com.apple.systempreferences" }
  .map { $0.processIdentifier }
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let windows = (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? [])
  .filter { pids.contains($0[kCGWindowOwnerPID as String] as? pid_t ?? -1) }

// 某次系统设置实验中，sheet 和主窗均为 layer 0；按面积曾可区分
// 实际选择还需结合身份与当前窗口列表，不把最大面积当主窗口契约
// 输出 JSON 供 Node 侧 JSON.parse；`--dump` 模式把所有窗口的 layer / bounds 全打出来便于核对
```

`swift build --product <name>` 后二进制在 `.build/debug/<name>`；发布用 `--triple arm64-apple-macosx11.0` 与 `x86_64-...` 各编一次再 `lipo -create`

## 捕捉偶现的系统弹层

用上面的 `--dump` 模式做后台轮询观测，命令见 [capture-recipes.md](capture-recipes.md)「观测偶现的系统弹层」。每秒采样只适合持续足够长的状态，更短现场需要事件式采样
