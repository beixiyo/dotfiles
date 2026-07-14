---
name: open-nvim
description: 用 open-nvim 在 Neovim 中打开指定文件（可携带行列号），仅在用户主动调用时使用
---

# open-nvim

调用 `~/.local/bin/open-nvim` 把文件在运行中的 Neovim 实例里打开，并精确跳转到指定行列

## 工具

使用 **Bash** 执行：

```bash
~/.local/bin/open-nvim <file>[:<line>[:<col>]]
```

## 支持的调用格式

| 用户输入示例 | 对应命令 |
|---|---|
| `/open-nvim src/foo.ts` | `~/.local/bin/open-nvim src/foo.ts` |
| `/open-nvim src/foo.ts:42` | `~/.local/bin/open-nvim src/foo.ts:42` |
| `/open-nvim src/foo.ts:42:7` | `~/.local/bin/open-nvim src/foo.ts:42:7` |
| `/open-nvim src/foo.ts 42 7`（分参） | `~/.local/bin/open-nvim src/foo.ts 42 7` |

## 执行步骤

1. 从用户的消息里解析出文件路径，以及可选的行号、列号
2. 组装命令，**路径统一用 `~/.local/bin/open-nvim`（不硬编码用户名）**
3. 用 Bash 执行，将命令的 stdout/stderr 原样回显给用户
4. 若脚本输出 `No running Neovim instance found`，告知用户当前没有活跃的 Neovim 实例

## 注意

- 仅在用户主动键入 `/open-nvim` 时调用，**不要自动触发**
- 文件路径若为相对路径，保持原样传入，脚本内部会用 `realpath` 解析
- 若未提供行列号，脚本默认跳转到第 1 行第 1 列
