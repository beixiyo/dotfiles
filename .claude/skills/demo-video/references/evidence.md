# 路线 E：测试取证录屏（带接口耗时）

录真实应用的测试过程，画面上实时显示「已等待 Ns · 最新事件 X」，同时从真实网络响应里取精确耗时，给产品、后端或 QA 看「界面怎么反应、后端多久回来」

和路线 C 的区别：

| | C. 录制真实操作 | E. 测试取证录屏 |
|---|---|---|
| 目的 | 好看的演示成片 | 证明行为与耗时，配合测试报告 |
| 驱动 | `record.ts` 自己启动浏览器 | `playwright-cli` 已有会话（复用登录态），`run-code` 执行 |
| 画面 | CDP 逐帧，2x 高清，可后期推镜 | `page.screencast`，带章节卡和提示条 |
| 数据 | 无 | 网络日志 → 每个请求、每个流式事件的到达时间 |
| 未上线接口 | 不涉及 | 可用 `context.route` 写有状态的 mock 服务端 |

## 文件

```
scripts/evidence/
├─ lib.js     公共函数，由 build.sh 拼进每个场景
└─ build.sh   build.sh <scene.body.js> <out.js> <产物目录>
```

`run-code` 只接受一个 `async page => {}` 函数，不支持 import，所以用 build.sh 把 `lib.js` 和场景主体拼成一个文件，并注入 `const OUT = '<产物目录>'`

| 函数 | 作用 |
|---|---|
| `installNetLog(page, { match })` | 包住 `window.fetch`，按 URL 正则记录请求；逐行解析 SSE，记下每个事件名（`event:` 行或 JSON 的 `type` / `event` 字段）的到达时间 |
| `record(page, name, fn, size?)` | 录 `OUT/videos/<name>.webm`；出错也会停止录制；视口与 size 不一致时直接报错 |
| `chapter(page, title, desc, ms?)` | 全屏章节卡 |
| `hud(page, text)` / `hudClear()` | 顶部提示条，替换时不闪烁 |
| `waitFor(page, label, pred, { timeout, match })` | 每秒检查条件并刷新提示条，返回耗时（约 1s 精度，给观众看） |
| `netState(page, match)` | 最新一条请求的序号、状态、最新事件、是否结束 |
| `waitNetDone(page, match, before, label)` | 等到请求数超过 before 且最新一条已读完 |
| `typeSlowly(locator, text, delay?)` | 逐字输入 |
| `hideSelectors(page, selectors)` | 隐藏调试浮层，不进录屏 |
| `timings(page, match)` | 精确耗时表：`headersMs`、`firstMs[事件名]`、`endMs`，相对请求发出时刻 |

## 步骤

1. 在**产物目录**下执行所有 `playwright-cli` 命令：会话与当前目录绑定，换目录就找不到会话
2. 打开会话并登录，**先存一份登录态**：会话崩溃后 `--persistent` 也可能丢登录
   ```bash
   cd "$OUT"
   playwright-cli -s=ev open http://localhost:5173 --persistent
   # 登录……
   playwright-cli -s=ev state-save auth.json      # 崩溃后 state-load auth.json 恢复；含 token，用完删除
   playwright-cli -s=ev resize 1440 900           # 必须用 CLI 调；run-code 里 setViewportSize 仍会留灰边
   ```
3. 写场景主体 `s01.body.js`（模板见下），拼接并执行，返回值存成 JSON
   ```bash
   B=~/.claude/skills/demo-video/scripts/evidence/build.sh
   $B s01.body.js s01.js "$OUT"
   playwright-cli -s=ev --raw run-code --filename=s01.js > runs-01.json
   ```
4. 抽帧验证（recording.md 的「抽帧拼图」），确认提示条、章节卡、关键画面都在
5. 报告里的数字取 `runs-*.json` 的 `timings`，不取提示条上的秒数

## 场景模板

```js
// s01.body.js：lib.js 的函数和 OUT 可直接用
const M = '/api/chat'                                    // 要计时的请求，正则源码
await installNetLog(page, { match: '/api/' })            // 每个会话装一次，之后的调用直接返回
await page.reload()                                      // initScript 从下一次导航起生效
await hideSelectors(page, ['#dev-toolbar'])

const result = await record(page, 's01-send', async () => {
  await chapter(page, '场景 1：发送后等待回答', '真实后端 · 顶部显示等待时长和最新事件')
  const before = (await netState(page, M)).count
  await typeSlowly(page.getByRole('textbox'), '你好')
  await page.keyboard.press('Enter')
  const ms = await waitNetDone(page, M, before, '已发送，等待后端')
  await hud(page, `回答完成 · ${(ms / 1000).toFixed(1)}s`)
  await page.waitForTimeout(2500)                         // 给观众看结果的时间
  await page.screenshot({ path: `${OUT}/shots/s01-done.png` })
  return { ms }
})
return JSON.stringify({ result, timings: await timings(page, M) })
```

## 后端还没上线的接口：有状态 mock

`playwright-cli route` 命令只能返回固定内容。接口之间有联动（如 PUT 后 GET 结果变化）时，在 `run-code` 里用 `context.route` 写一个最小服务端，状态挂在 context 上，场景脚本可以直接调用它模拟后端事件：

```js
async page => {
  const ctx = page.context()
  if (ctx.__mock) return 'already'                       // route 会累积，必须防重复注册
  const state = ctx.__mock = { items: [], log: [] }
  await ctx.route(/\/api\/items$/, (route) => {           // 正则比 glob 更不容易漏 query 和跨端口
    state.log.push({ t: Date.now(), method: route.request().method() })
    return route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ items: state.items }) })
  })
  state.push = (item) => state.items.unshift(item)        // 场景里 page.context().__mock.push(...) 模拟后端事件
  return 'installed'
}
```

mock 只能证明客户端按接口文档工作，不能证明真实后端也这样做；报告里写明哪些画面用了 mock

## 为什么在页面里包 fetch，而不用 Playwright 的网络接口

- 读普通 JSON 接口：`page.on('response')`、`waitForResponse`、CLI `requests` / `response-body` 都好用，返回内容与直接请求后端一致
- 读流式响应的**中途**时间点：`response.body()` 要等响应结束才返回；`route.fetch()` + `fulfill()` 会把整段流缓冲后一次交给页面，界面的流式效果和首字时间都失真
- 所以要测 SSE 首字、某个事件何时到达，就用 `installNetLog`；它读 `resp.clone()`，业务代码拿到的原始流不受影响
- `installNetLog` 只覆盖 fetch；XHR、EventSource、WebSocket 需要另行处理

## 坑

- **run-code 沙箱没有 `URL`、`require`、`process`、`fs`**：用到就会让会话崩溃，之后的命令只报 `Session closed`。原始报错在 `~/Library/Caches/ms-playwright/daemon/<hash>/<session>.err`
- **网络日志在页面里**：每次导航都会清空，跨导航的数据要先 `timings()` 取出
- **提示条和 route 跨 run-code 保留**：上一次脚本中途出错留下的提示条会进下一段视频，用 `record()` 包裹可以避免；已经残留时重开会话
- **注册时机**：在请求发出后才注册的监听或 route 拦不到那次请求；首屏请求要先注册再 reload
- **Service Worker（如 MSW）**处理的请求，`route` 和 `page.on('response')` 都看不到：先在页面里查 `navigator.serviceWorker.getRegistrations()`，有就关掉 MSW；Playwright 的 `serviceWorkers: 'block'` 是创建 context 时的参数，playwright-cli 下怎么传未验证
- **提示条秒数有约 1s 延迟**：它靠每秒轮询；精确值以 `timings()` 为准
- **CLI `request N` 会打印 `Authorization` 头**，分享日志前脱敏

## 交付

1. 压缩：保持时长，降分辨率和帧率
   ```bash
   ffmpeg -v error -i in.webm -vf "scale=1280:-2,fps=15" -c:v libvpx-vp9 -crf 40 -b:v 0 -an out.webm
   ```
   实测：9 段共 43MB 压到约 10.5MB，界面文字仍清楚
2. 要发给别人的单文件报告：把视频转成 `data:video/webm;base64,...` 写进 `<video src>`，不留本机路径。实测 14MB 的单文件 HTML 浏览器能正常打开和播放
3. 用本地 HTTP 服务打开成品检查每段视频都能加载（`video.readyState`、`duration`），不要只看 `file://`
4. 测试数据被改动（新建、编辑了什么）要写进报告；含 token 的 `auth.json` 等文件删除
