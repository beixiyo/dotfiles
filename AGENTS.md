# Dotfiles 项目概览

开发环境配置集合，所有模块均在 `~` 目录下，按工具独立组织

**Mac 键位前提**：Karabiner 在普通 GUI 应用中交换左 Ctrl↔左 Cmd，模拟 Windows/Linux 键位习惯；Kitty、WezTerm、Ghostty、Neovide、Terminal、iTerm2 和远程客户端被豁免，终端内物理 Ctrl 仍按 `ctrl+` 配置

---

## 模块一览

| 模块 | 路径 | 说明 |
|------|------|------|
| **Zsh** | `~/.zsh/` + `~/.zshrc` | 主力 Shell，模块化配置 |
| **Neovim** | `~/.config/nvim/` | 编辑器，含自定义插件管理系统 |
| **Tmux** | `~/.config/tmux/` | 终端复用器，模块化配置 + TPM 插件 |
| **Kitty** | `~/.config/kitty/` | 终端模拟器 |
| **WezTerm** | `~/.config/wezterm/` | 终端模拟器（跨平台，兼顾 Windows） |
| **Ghostty** | `~/.config/ghostty/` | 终端模拟器 |
| **Karabiner** | `~/.config/karabiner/` | 键盘改键（macOS，普通 GUI 应用交换左 Ctrl↔左 Cmd，终端与远程客户端豁免） |
| **Yazi** | `~/.config/yazi/` | 终端文件管理器 |

---

## Zsh（`~/.zsh/`）

**入口**：`~/.zshrc` → `~/.zsh/zshrc`（按顺序 source 各模块）

**加载顺序**：`env.zsh` → `secret.zsh` →（交互式 shell 限定）→ tmux 交互入口 → `options.zsh` → `plugins.zsh` → `completions.zsh` → `tools.zsh` → `aliases.zsh` → `functions/index.zsh` → `keybindings.zsh` → `notify.zsh`

**核心架构："Zsh 为壳，Bun 为核"**
- Zsh 负责 TTY 交互与 UI（fzf）
- Bun（TypeScript）负责复杂逻辑与数据处理
- Bun 脚本位于 `functions/bun/src/*.ts`，Zsh 函数位于 `functions/*.zsh`

**函数模块**（`functions/`）：`git` / `dev` / `docker` / `download` / `file-ops` / `fzf` / `mihomo` / `net` / `process` / `proxy` / `ssh` / `sys` / `yazi` / `pkg/` / `_actions/` / `_preview/` / `bun/`

**插件**（`plugins/`）：zsh-autosuggestions / fast-syntax-highlighting / zsh-history-substring-search / zsh-vi-mode

**运行时工具**：starship（prompt）、mise（版本管理，替代 vfox）、zoxide（智能 cd）、fzf（模糊搜索）

> 详细开发规范见 `~/.zsh/AGENTS.md`（Bun + fzf 协作模式、TTY 避坑指南）

---

## Neovim（`~/.config/nvim/`）

**入口**：`init.lua` → 依次加载 `options` → `neovide` → `clipboard` → `pack` → `keymaps` → `autocmd` → `cmd`

**插件管理**：基于 Neovim 0.12+ 原生 `vim.pack` API 的自实现系统（字段命名与 lazy.nvim 对齐），含 GUI（`:PluginManager`）
- `lua/plugins/manager/user-picks.lua` — 用户勾选状态（GUI 自动写入）
- `lua/plugins/specs/` — 插件声明，按 `code/` / `tools/` / `ui/` 分类
- `lua/pack/` — 包管理核心（loader / sync / build / scan 等）

**技术栈**：telescope（picker）、blink.cmp（补全）、lspconfig（LSP）、nvim-treesitter（语法）、tokyonight（主题，本地 fork 在 `vendors/`）

**IDE 类型支持**：`bun run scripts/gen-luarc.ts` 更新 `.luarc.json` 中插件类型定义

> 详细架构见 `~/.config/nvim/AGENTS.md`

---

## Tmux（`~/.config/tmux/`）

**入口**：`tmux.conf` → 按功能 source 各 conf 模块

**配置模块**（`conf/`）：`options` / `copy-mode` / `pane` / `plugins` / `status` / `window` / `hide-bar`

**插件**（TPM 管理）：tmux-sensible / tmux-cpu / Catppuccin / tmux-resurrect / tmux-continuum

**与终端集成**：Kitty 默认使用 tmux 模式（`keys-tmux.conf`），tab/pane 操作全交由 tmux 管理

---

## 终端模拟器（Kitty / WezTerm / Ghostty）

三个终端保持一致的快捷键方案：

| 功能 | 快捷键 |
|------|--------|
| 新建/关闭 Tab | `Ctrl+Shift+T` / `Ctrl+Shift+W` |
| 切换 Tab | `Ctrl+1~8` |
| 分屏 | `Ctrl+Alt+-`（水平）/ `Ctrl+Alt+\`（垂直） |
| 字体缩放 | `Ctrl+=` / `Ctrl+-` / `Ctrl+0` |
| 右键粘贴 | 统一配置 |

**特殊键透传**：`Ctrl+`` 与 `Ctrl+Shift+L` 由终端显式发送 CSI-u 序列，绕过 legacy 编码和 tmux 重编码，分别供 Neovim 终端切换与多光标使用

**Kitty 双模式**：支持 native（Kitty 原生 tab + pane + smart-splits）和 tmux（tab/pane 全交给 tmux）两种窗口管理模式，当前默认 tmux 模式

**WezTerm 特有**：启用 Kitty keyboard protocol；native 模式按前台进程判断是否把 `Ctrl+Alt+H/J/K/L` 与方向键透传给 Neovim，tmux 模式则显式发送 CSI-u 序列

---

## Karabiner（`~/.config/karabiner/`）

模拟 Windows 键位习惯：

| 规则 | 效果 |
|------|------|
| 普通 GUI 应用交换左 Ctrl↔左 Cmd | 左 Ctrl 发送左 Cmd、左 Cmd 发送左 Ctrl；终端、Neovide 与远程客户端豁免 |
| Alt+Tab → Mission Control | 模拟 Windows 的 Alt+Tab 切应用 |
| Ctrl+Shift+方向键 → Option+Shift+方向键 | 单词级选择（Windows 行为） |
| 禁用 Cmd+H | 防止误触隐藏应用 |

**注意**：终端应用位于 Karabiner 豁免列表，终端配置中的 `ctrl+` 直接对应物理 Ctrl；普通 GUI 应用才应用左 Ctrl↔左 Cmd 交换

---

## Yazi（`~/.config/yazi/`）

终端文件管理器，Vim 风格键位（h/j/k/l 导航）。配置文件：`yazi.toml`（显示设置）、`keymap.toml`（快捷键）、`theme.toml`（主题）。插件：`fzfo.yazi`（fzf 集成）
