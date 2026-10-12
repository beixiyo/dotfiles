---
name: open-nvim
description: 用 open-nvim 在运行中的 Neovim 实例打开文件并精确跳转行列；多文件时填入 quickfix 并打开面板。仅在用户主动键入 /open-nvim 时调用，不要自动触发
---

调用 `~/.local/bin/open-nvim` 把文件在运行中的 Neovim 实例里打开，并精确跳转到指定行列；多文件时填入 quickfix 并打开面板。所有参数同一格式，可传任意多个：

```bash
~/.local/bin/open-nvim src/foo.ts:42:7          # 单文件：行列可缺省，默认 1:1
~/.local/bin/open-nvim a.ts:10 b.lua:5:2 c.md   # 多文件：同一文件可出现多次
```

## 执行步骤

1. 从用户的消息里解析出文件路径列表，以及每项可选的行号、列号
2. 用 Bash 执行，将命令的 stdout/stderr 原样回显给用户
3. 若脚本输出 `No running Neovim instance found`，告知用户当前没有活跃的 Neovim 实例

## 注意

- 文件路径若为相对路径，保持原样传入，脚本内部会用 `realpath` 解析
- 列号按 UTF-16 码元计（含中文等多字节字符的行与浏览器/编辑器字符列一致），不是字节列；不确定时省略列号
