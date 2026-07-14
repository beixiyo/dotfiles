---
name: how-to-test
description: 完成代码改动后，给出有实际信号的验证步骤；只验证行为、集成、类型、构建或真实副作用，避免低价值脚本和实现细节断言
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
3. 只为高信号自动验证写 `/tmp/<slug>-test/` 脚本
4. 脚本落盘后自己先跑一遍
5. 回复只给短命令、预期结果和必要手测步骤

验证点不超过 6 个，按核心功能、边界情况、回归风险排序

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
- **Neovim/Lua**：公开 API/命令可 headless；鼠标、浮窗、可视选区只给手测步骤

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
