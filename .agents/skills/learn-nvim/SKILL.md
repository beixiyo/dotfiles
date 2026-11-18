---
name: learn-nvim
description: >-
  用前端开发者熟悉的概念类比来讲解 Neovim 概念（window、buffer、tabpage、选项作用域、autocmd、事件时序、Lua API 等），并标注每个类比的可靠程度
  用户想学习、理解某个 Neovim 概念（如「nvim 里的 X 是什么」「autocmd 和 addEventListener 有什么区别」）等情况时使用；不用于调试插件、写配置或普通使用问题
---

# 用前端概念讲 Neovim

读者是有前端经验的开发者。他们已经有 DOM、事件、异步的心智模型，借用这些模型能最快理解 Neovim；但类比一旦被当成等价就会埋坑，所以每个类比都要说明哪里不同

## 怎么讲

1. **先类比，再补差异**：每个概念先给前端或通用工程里的对应物，再说清楚「和前端不同的地方」
2. **标注类比强度**，让用户知道能信多少：
   - 完全等价：直接套用不会错
   - 近似：语义接近，但有会影响行为的差别，要写出差别
   - 仅作类比：只帮助建立直觉，机制并不相同，不要据此推断行为
3. **只讲用户问的**：问 *X 是什么* 就答 X，不顺手把整个子系统教一遍
4. **先一句话直接答，再用表格补细节**，避免长段叙事
5. **不用 Neovim 术语解释 Neovim 术语**：「autocmd 是自动命令」这种循环定义没有信息量，必须落到用户已有的概念上
6. **解释 Lua 代码时补上参数形状**（`---@param` / `---@return`），Lua 没有类型，前端用户需要靠它读懂调用

## 事实以实测为准

Neovim 的行为随版本变化，类比和细节都不要凭记忆写成结论：

- 先查 `:help <topic>`，必要时用 `nvim --headless -u NONE -l probe.lua` 做最小实验确认，结论里标注 `nvim --version`
- 分清稳定的概念（window 显示 buffer、选项分 global / window-local / buffer-local）和易变的实现细节（继承规则、事件触发时机、各 API 的边界行为）。后者只在实测过之后才断言
- 区分 `vim.api.nvim_*`（底层 C API）和 `vim.fn.*`（Vimscript 函数桥），用户常因混用找不到文档，要明确指路
- Vim 和 Neovim 不通用：`vim.api`、`vim.opt`、浮窗 `nvim_open_win`、内置 LSP 等是 Neovim 独有，用户问到时说明，不要默认「Vim 也一样」
