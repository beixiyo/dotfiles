---
name: how-to-test
description: 为代码改动选择并执行有信号的验证，提供复验步骤；适用于行为、集成、类型、构建与截图验证，避免低价值脚本和实现细节断言
---

# how-to-test

## 原则

- 先判断测试是否有信号；没有就不写脚本
- 自动验证只覆盖可客观失败的点：类型/构建、真实函数或 API、组件接线、集成链路、bug 复现、写后读回
- 不为源码字符串、className、图标名、文案、import 存在性写断言
- UI 视觉微调、布局观感、浮层焦点、鼠标交互优先手测或截图验证
- 已被 typecheck/lint 覆盖的语法级问题，不再包一层脚本
- 如果只能做低价值自动化，直接说明未新增脚本及原因

## 流程

1. 识别改动和风险点
2. 区分：可自动验证 / 需手测 / 不值得测
3. 优先运行项目已有的相关测试、类型检查或构建；存在重要覆盖缺口时才补充测试，临时验证脚本放在 `/tmp/<slug>-test/`
4. 新增测试或脚本后自己运行，检查失败是否由本次改动引起
5. 回复只给短命令、预期结果和必要手测步骤

验证范围按核心功能、边界情况和回归风险选择。相关检查通过后，无新改动、失败或未解决风险就不扩大或重复验证

## 脚本入口

按本机可用命令选择入口，优先级固定为 **ts → js → py → sh**：

| 条件 | 入口文件 | 运行命令 |
|------|----------|----------|
| `command -v bun` | `run.ts` | `bun run /tmp/<slug>-test/run.ts` |
| `command -v node` 或 `command -v nodejs` | `run.js` | `<node-cmd> /tmp/<slug>-test/run.js` |
| `command -v python3` 或 `command -v python` | `run.py` | `<python-cmd> /tmp/<slug>-test/run.py` |
| 兜底 | `run.sh` | `bash /tmp/<slug>-test/run.sh` |

脚本约定：

- 清理并重建 fixture，保证可重复运行
- 打印 `PASS:` / `FAIL:`，最后汇总 `N PASS / M FAIL`
- 使用真实源码、真实公开 API 或真实运行入口
- 验证完清理临时产物；需要保留时支持 `KEEP=1`

## 技术栈提示

- **TypeScript/JS**：优先跑项目已有 typecheck/test/build；纯逻辑可用真实模块断言输入输出
- **前端 UI**：组件接线用 typecheck/lint；有可运行页面时优先用 `playwright-cli` 做浏览器交互/截图验证；不能跑页面时再给手测步骤；视觉不写 class 字符串断言
- **CLI/zsh**：覆盖正常路径、空输入、依赖缺失、退出码和文件/进程副作用
- **外部系统**：写入后必须读回确认，例如飞书状态更新后重新查询
- **Neovim/Lua**：公开 API/命令可 headless；鼠标、浮窗、可视选区等交互在自动化能覆盖真实故障条件时自行验证，无法模拟的部分再给手测步骤，并说明证据缺口。headless 状态断言不能替代真实界面的视觉或交互证据

## 报告形式：Markdown 还是 HTML

| 场景 | 形式 |
|------|------|
| 只有命令、断言、少量手测步骤，没有截图 | 回复里的 Markdown，按下方「输出」模板 |
| 有截图，且截图 ≥ 5 张或覆盖多个状态 / 矩阵行 | 落盘 `index.html`，回复里仍给 Markdown 结论表 + 一键打开命令 |
| 单张截图佐证一个点 | 直接在回复里给截图路径，不建 HTML |

HTML 报告不替代回复：回复必须自带结论表、FAIL 列表和 `open <index.html>` 命令，用户不打开页面也能知道结果

## 截图留档

有截图就必须分类落盘，禁止散落在 `/tmp` 根目录或只存在于 playwright 输出目录：

- 根目录：scratchpad 下 `<slug>-shots/`
- 一个状态 / 场景一个子目录，两位序号 + 英文短名，如 `01-login-empty`、`07-checkout-monthly-cancelled`，序号按执行顺序排，前置条件（如后台配置取证）放 `00-xxx`
- 文件名同样序号 + 内容，如 `01-settings.png`、`03-dialog-open.png`；同类状态截同一套基准图，方便横向对比
- 断言依据不靠读图：把 DOM 取值、接口响应等原始数据存成同目录 JSON（如 `state.json`），报告里的 PASS / FAIL 引用它
- 委派给子代理时，把根目录、子目录命名和基准图清单写进 prompt，收尾时抽查目录结构再汇总

## HTML 报告约定

- 单文件 `index.html` 放在截图根目录，图片用相对路径，`open <path>/index.html` 即可查看
- 允许用 Tailwind Play CDN（`<script src="https://cdn.tailwindcss.com"></script>`）省掉手写样式；不引入其它需要构建的依赖
- 顶部：总览（N 组 / PASS / FAIL）+ 各组跳转锚点
- 每组一个 section：标题写状态名，正文先放「期望 vs 实测」对照表（期望来自 PRD / 需求，实测来自 JSON 取值），再平铺该组截图，`<a href>` 包住 `<img>` 让点击能开原图，末尾 PASS / FAIL 徽标和说明
- FAIL 和可疑点单独汇总一节，每条写现象、期望、对应截图文件名

## 输出

````markdown
## 测试：<改动简述>

### 自动验证
```bash
<命令>
```
预期：<具体 PASS / 输出 / 副作用>

### 手动验证（如需要）
1. <操作> -> 预期：<可观察结果>
````

有 HTML 报告时在末尾追加：

````markdown
### 截图报告
| 状态 | 目录 | 结果 |
|------|------|------|
| <状态> | `<NN-slug>` | PASS / FAIL |

FAIL / 可疑点：<现象 -> 期望 -> 截图文件名>

```bash
open <截图根目录>/index.html
```
````
