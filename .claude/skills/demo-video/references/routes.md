# 路线 B / C

路线 A 见 [dom-demo.md](dom-demo.md)，录制与编码见 [recording.md](recording.md)。B、C 涉及的库 API 以项目实际版本为准，动手前用 search skill 查当前文档，不凭记忆写

## B. 代码渲染视频

时间由帧号驱动，每帧确定、可复现，不掉帧；渲染慢的复杂动画也能输出流畅 60fps

| 工具 | 写法 | 适合 |
|---|---|---|
| Remotion | React 组件按 `useCurrentFrame()` 派生画面，`interpolate` / `spring` 做缓动，无头 Chrome 逐帧截图后交 ffmpeg | 宣传片、字幕、转场、嵌入录屏素材做后期 |
| Motion Canvas / Revideo | TS generator 写时间线（`yield*` 串联动画） | 讲解动画、代码逐行高亮、示意图 |
| 自写 HTML + 控制时钟 | Playwright `page.clock` 接管 JS 计时器，逐帧推进并截图 | 轻量需求，不想引框架 |

要点：
- 一切动画都必须是帧号的函数；CSS transition / 真实 setTimeout 在逐帧渲染里不可控，要改成按帧计算
- 嵌入录屏素材时用高分辨率源（2x），后期放大才不糊
- Remotion 商业使用前确认许可证条款
- 自写方案注意：`page.clock` 只管 JS 计时器，不管 CSS 动画；CSS 动画需改成 JS 驱动或用 Web Animations API 手动设置 `currentTime`

## C. 录制真实 Web 操作

用 Playwright 场景脚本驱动真实应用，`record.ts --scenario` 边跑边录

场景脚本：

```ts
/** demo.scenario.ts：默认导出，参数只有 page */
export default async function ({ page }) {
  await page.getByRole('button', { name: '新建' }).click()
  await page.waitForTimeout(400) // 给观众反应时间，比真实操作慢一拍
  await page.getByRole('textbox').pressSequentially('Hello', { delay: 80 }) // 逐字输入才有打字感
}
```

节奏技巧：
- 用 `pressSequentially(text, { delay })` 而不是 `fill`；每个动作后停 300–600ms
- `scrollIntoViewIfNeeded` 是瞬移；要平滑滚动用 `page.evaluate(() => el.scrollIntoView({ behavior: 'smooth', block: 'center' }))` 后等待
- 真实光标不会出现在 screencast 里：需要可见光标时，注入一个跟随 `mousemove` 的绝对定位光标元素，`page.mouse.move(x, y, { steps: 20 })` 产生平滑轨迹
- 登录态、种子数据在场景前准备好，录制只包含要展示的动作
- 数据要稳定：固定时间（`page.clock.setFixedTime`）、mock 随机内容，保证每次复录一致

### C+：后期平滑推镜（Screen Studio 效果）

1. 录制：整视口、`--dpr 2`、输出 MP4（`--format mp4`），场景脚本里记录每次点击的坐标与时间戳到 JSON
2. 后期：用路线 B（如 Remotion）把录屏作为视频素材放进合成，按事件 JSON 用弹簧/缓动计算每帧的 `scale` 与 `translate`：推近点击点 → 停留 → 拉回；再叠加放大光标、点击涟漪、字幕
3. 不推荐：只用 ffmpeg `zoompan`。坐标取整会抖，需要先放大再缩回才能缓解，效果仍不如逐帧计算
4. 不推荐：录制时给 `<html>` 加 CSS transform 放大。画面清晰但会干扰页面布局与命中测试，真实应用里容易出错
