---
name: demo-video
description: 制作产品演示视频、动画或 GIF 时使用：官网/README 演示动画、前端代码转视频、录制网页或 Web 应用操作、平滑推镜放大、GIF/MP4 压缩与无缝循环。先按目标选路线（DOM 剧本动画 / 代码渲染视频 / 录制真实操作 / 纯后期），再用通用录制脚本产出并抽帧验证
---

# demo-video

## 先认清能力边界

- 不能直接看视频，也不能直接生成视频：一律写代码产出帧，再用 ffmpeg 合成
- 验证靠抽帧拼图后用 Read 看图；首尾帧单独对比（循环接缝）、运动中段单独抽（推镜是否错位）
- 说"已完成"前至少抽过一次成片帧；只看过开发页截图不算验证了视频

## 选路线

| 目标 | 路线 | 产物 | 详见 |
|---|---|---|---|
| 官网首屏可交互演示，同时要 README GIF | **A. DOM 剧本动画 + 录制** | 网页内实时动画；录成 GIF/MP4 | [dom-demo.md](references/dom-demo.md) |
| 宣传片、带字幕转场的成片、逐帧精确 | **B. 代码渲染视频**（Remotion / Motion Canvas） | MP4 | [routes.md](references/routes.md) · B |
| 展示真实 Web 应用的操作流程 | **C. 录制真实操作**（Playwright 场景脚本）+ 可选后期推镜 | GIF/MP4 | [routes.md](references/routes.md) · C |
| 已有素材只需剪辑、加速、转 GIF | **D. 纯 ffmpeg 后期** | GIF/MP4 | [recording.md](references/recording.md) · ffmpeg 配方 |

判断要点：
- 演示要同时出现在官网（可交互、跟随主题和语言）和 README → A，一份实现两处复用
- 演示的是**真实产品行为**、UI 会持续迭代 → C，免得维护一份模仿品；需要推镜效果再接 B 做后期
- 需要配音、字幕、片头片尾、多段素材拼接 → B
- 路线 A 的模拟界面必须对照真实产品源码复刻（文案、颜色、状态流转），凭印象做必然失真

## 通用录制脚本

`scripts/record.ts`：任意页面或元素 → GIF / MP4。CDP 逐帧抓取（2x 清晰度、真实时间戳）+ ffmpeg 按真实时长合成。在**目标项目目录**运行（需能解析到 `playwright` 或 `@playwright/test`）：

```bash
S=~/.claude/skills/demo-video/scripts/record.ts

# 自动播放的循环动画：页面每轮开始把属性 +1，录一整轮，首尾无缝
bun run $S --url 'http://localhost:5173/?demo=solo' --selector '[data-demo-stage]' --stop loop:data-demo-loop

# 固定时长
bun run $S --url http://localhost:5173 --stop duration:6 --format gif,mp4

# 真实操作：场景脚本默认导出 async ({ page }) => void，跑完即停
bun run $S --url http://localhost:5173 --scenario ./demo.scenario.ts --out docs/demo

# 服务没开时自动启动、录完关闭
bun run $S --url http://localhost:5173 --serve 'pnpm dev' --stop duration:5
```

`--help` 看全部选项。默认 GIF 720px / 12fps / 128 色 / 不抖动，依据见 [recording.md](references/recording.md) 的「GIF 取舍」。项目要长期复用时，在 package.json 加脚本固化参数，而不是复制一份录制器

录制结束会做静止自检：录制区域几乎全程没变时（场景选择器或坐标没命中、页面没渲染、loading 页占用大量时间等典型症状）在结尾打印警告，成片照常输出。看到警告必须抽帧确认，不能直接交付

## 页面侧约定（路线 A / 循环录制）

- 独立录制入口：`?demo=solo` 之类的参数只渲染演示本身，固定宽度，不受导航与首屏布局影响
- 循环边界：每轮开始把 `data-demo-loop` 之类的属性 +1；结尾淡出到与开头相同的画面
- 录制模式忽略视口可见性（IntersectionObserver）与语言自动判定，语言由 URL 参数指定且不写存储

## 交付前检查

- [ ] 成片抽帧看过：开场、关键动作、运动中段、结尾；明暗主题和多语言各至少一张
- [ ] 循环素材首尾帧一致（[recording.md](references/recording.md) 的「无缝循环」）
- [ ] 体积符合用途：README GIF 建议 ≤ 5MB，超了先降 fps，再降颜色数，最后降宽度
- [ ] 窄屏下演示构图不崩（路线 A），开发页无横向溢出
- [ ] 不因 `prefers-reduced-motion` 把官网演示定格成静态：用户会视为降级；需要照顾时只去掉大幅位移，保留播放
- [ ] 告知用户一键复录命令；自动启动的服务已结束，没有残留进程
