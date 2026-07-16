# dotfiles

> 轻量、可恢复、适合远程开发的全终端工作区

<p align="center"><a href="README.md">English</a> | 中文</p>

<p align="center">
  <a href="https://neovim.io/"><img src="https://img.shields.io/badge/Neovim-57A143?style=flat&amp;logo=neovim&amp;logoColor=white" alt="Neovim"></a>
  <br>
  <a href="https://www.lua.org/"><img src="https://img.shields.io/badge/Lua-2C2D72?style=flat&amp;logo=lua&amp;logoColor=white" alt="Lua"></a>
  <a href="https://bun.sh/"><img src="https://img.shields.io/badge/Bun-000000?style=flat&amp;logo=bun&amp;logoColor=white" alt="Bun"></a>
  <a href="https://www.typescriptlang.org/"><img src="https://img.shields.io/badge/TypeScript-3178C6?style=flat&amp;logo=typescript&amp;logoColor=white" alt="TypeScript"></a>
  <a href="https://nodejs.org/"><img src="https://img.shields.io/badge/Node.js-5FA04E?style=flat&amp;logo=nodedotjs&amp;logoColor=white" alt="Node.js"></a>
  <br>
  <a href="https://github.com/tmux/tmux"><img src="https://img.shields.io/badge/tmux-1BB91F?style=flat&amp;logo=tmux&amp;logoColor=white" alt="tmux"></a>
  <a href="https://www.zsh.org/"><img src="https://img.shields.io/badge/Zsh-F15A24?style=flat&amp;logo=zsh&amp;logoColor=white" alt="Zsh"></a>
  <a href="https://starship.rs/"><img src="https://img.shields.io/badge/Starship-DD0B78?style=flat&amp;logo=starship&amp;logoColor=white" alt="Starship"></a>
  <a href="https://mise.jdx.dev/"><img src="https://img.shields.io/badge/Mise-8B2252?style=flat" alt="Mise"></a>
  <a href="https://yazi-rs.github.io/"><img src="https://img.shields.io/badge/Yazi-FFA500?style=flat" alt="Yazi"></a>
  <br>
  <a href="https://sw.kovidgoyal.net/kitty/"><img src="https://img.shields.io/badge/Kitty-000000?style=flat" alt="Kitty"></a>
  <a href="https://ghostty.org/"><img src="https://img.shields.io/badge/Ghostty-5C4EE5?style=flat&amp;logo=ghostty&amp;logoColor=white" alt="Ghostty"></a>
  <a href="https://wezterm.org/"><img src="https://img.shields.io/badge/WezTerm-4E49EE?style=flat&amp;logo=wezterm&amp;logoColor=white" alt="WezTerm"></a>
</p>

![workflow](./docs/assets/workflow.png)

<video muted autoplay loop controls src="https://github.com/user-attachments/assets/b26a9b91-1898-4fcb-99b3-692911eb10ed" title="终端工作流演示"></video>

<p align="center"><strong>Neovim 配置、使用与插件展示：<a href=".config/nvim/README.md">快速开始 →</a></strong></p>

这个仓库可以把一台新机器的终端变成完整的开发工作区：Zsh 提供 Shell，tmux 持久保存会话，Kitty / Ghostty / WezTerm 负责终端显示，Neovim 处理代码、Git、笔记和 AI 辅助工作流。终端分屏与编辑器分屏共用同一套快捷键，使用时更像一个完整环境，而不是多个互不相关的工具

<!--toc:start-->
- [dotfiles](#dotfiles)
  - [文档导航](#文档导航)
  - [从零开始安装](#从零开始安装)
  - [为什么选择全终端工作流](#为什么选择全终端工作流)
    - [开发运行时](#开发运行时)
  - [AI 工作流](#ai-工作流)
  - [终端操作](#终端操作)
  - [技术栈](#技术栈)
  - [Neovim](#neovim)
    - [Neovide 与 `nvd`](#neovide-与-nvd)
    - [插件](#插件)
  - [模块](#模块)
<!--toc:end-->

## 文档导航

[GitHub Wiki](https://github.com/beixiyo/dotfiles/wiki) 提供详细使用教程。可以直接从当前需要的工作流开始，不必按仓库目录从头阅读：

| 主题 | 文档 |
|---|---|
| Neovim 入门 | [模式与移动](https://github.com/beixiyo/dotfiles/wiki/nvim-learn-01-modes-and-movement) · [编辑与文本对象](https://github.com/beixiyo/dotfiles/wiki/nvim-learn-02-editing-and-text-objects) · [高级命令](https://github.com/beixiyo/dotfiles/wiki/nvim-learn-03-advanced-commands) |
| Neovim 工作流 | [快捷键技巧](https://github.com/beixiyo/dotfiles/wiki/nvim-guide-shortcut-tips) · [DAP 调试](https://github.com/beixiyo/dotfiles/wiki/nvim-debug-dap) · [Lua 配置](https://github.com/beixiyo/dotfiles/wiki/nvim-config-lua) |
| Shell 与终端 | [Zsh](https://github.com/beixiyo/dotfiles/wiki/zsh-guide-shell) · [Tmux](https://github.com/beixiyo/dotfiles/wiki/tmux-guide-keymaps) · [终端快捷键](https://github.com/beixiyo/dotfiles/wiki/terminal-guide-keymaps) · [Yazi](https://github.com/beixiyo/dotfiles/wiki/yazi-guide-keymaps) |
| 桌面环境 | [Niri](https://github.com/beixiyo/dotfiles/wiki/niri-guide-usage) · [Karabiner Windows 键位](https://github.com/beixiyo/dotfiles/wiki/karabiner-guide-windows-keymap) · [Linux 剪贴板历史](https://github.com/beixiyo/dotfiles/wiki/linux-guide-clipboard) |
| Neovim 开发 | [面向 TypeScript 开发者的 Lua](https://github.com/beixiyo/dotfiles/wiki/nvim-dev-lua-for-ts-devs) · [Neovim API](https://github.com/beixiyo/dotfiles/wiki/nvim-dev-api) · [插件路径](https://github.com/beixiyo/dotfiles/wiki/nvim-config-plugin-paths) |

## 从零开始安装

不熟悉终端也没关系。按照下面的顺序操作即可；每一步都完成后，再进入下一步

### 1. 选择并安装现代终端

先从下面三个终端中选择一个。它们都能使用这套配置，**只需要安装一个**：

- [Kitty](https://sw.kovidgoyal.net/kitty/) — **扩展性最强，推荐选择**。三个终端中只有 Kitty 的原生模式完整实现了接近 tmux 的窗口、分屏和布局交接能力，并支持平滑光标
- [Ghostty](https://ghostty.org/) — 支持自定义 shader，适合需要终端视觉效果的用户；功能相对直接，内存占用略高
- [WezTerm](https://wezterm.org/) — 跨平台的中庸之选，macOS、Linux 和 Windows 都能使用，并通过 Lua 脚本配置

安装脚本支持 macOS 和主流 Linux 发行版。Windows 用户可以安装 WezTerm，但后续 Shell 配置需要在 [WSL](https://learn.microsoft.com/windows/wsl/install) 中部署

### 2. 确认 Nerd Font

Nerd Font 为终端、Neovim 和提示符提供文件夹、Git、诊断等图标。**如果你已经安装并正在使用 Nerd Font，可以跳过这一步**

推荐下载 [Maple Mono NF](https://github.com/subframe7536/maple-font/releases)，也可以从 [Nerd Fonts](https://www.nerdfonts.com/font-downloads) 选择其他字体。安装后，在终端设置中把字体切换到对应的 Nerd Font

Linux（含 Arch）可以直接安装上游 Maple Mono NF 单包，避免 AUR split package 下载全量源码：

下面的命令需要 `curl` 和 `unzip`；如果系统还没有它们，可以先通过浏览器安装字体，或者完成第 4 步后再回来执行

```bash
mkdir -p ~/Downloads/maplemono && \
cd ~/Downloads/maplemono && \
curl -fL --retry 3 \
  -o MapleMono-NF.zip \
  https://github.com/subframe7536/maple-font/releases/latest/download/MapleMono-NF.zip && \
unzip -o MapleMono-NF.zip && \
sudo install -d /usr/local/share/fonts/MapleMono-NF && \
sudo install -m 644 ./*.ttf /usr/local/share/fonts/MapleMono-NF/ && \
sudo fc-cache -f

fc-list | grep 'MapleMono'
```

### 3. 下载配置仓库

先确保系统已经有 Git。没有 Git 时，根据系统执行一条安装命令：

```bash
# macOS
xcode-select --install

# Arch Linux
sudo pacman -S git

# Debian / Ubuntu
sudo apt install git

# Fedora
sudo dnf install git
```

然后克隆仓库并进入目录：

```bash
git clone https://github.com/beixiyo/dotfiles.git ~/dotfiles
cd ~/dotfiles
```

后面的 `./one-click-config/...` 命令都需要在 `~/dotfiles` 中执行

### 4. 安装命令行依赖

```bash
./one-click-config/setup-deps.sh
```

脚本会检测 pacman、apt、dnf、zypper 或 Homebrew，并安装 Zsh、Neovim、tmux、mise、Git、ripgrep、fd 等工具。只有确实需要安装系统软件包时才会请求管理员权限

### 5. 部署配置

大多数用户只需要第一条命令：

```bash
# 部署到当前用户
./one-click-config/setup-user.sh

# 可选：部署到指定用户
./one-click-config/setup-user.sh alice bob
```

不传参数时，脚本部署到当前用户，并询问是否配置其他用户。指定 `alice bob` 时，脚本会为这些用户部署；Linux 可以自动创建缺失用户，macOS 需要先在“系统设置”中创建账户

覆盖已有配置前，脚本会先询问，并可以备份到 `~/.dotfiles-backup-<timestamp>/`。管理员权限只用于创建用户、修改登录 Shell、配置 sudo 等必要步骤

### 6. 安装 Bun

```bash
# 本仓库只需要 Bun
mise use -g bun
```

Bun 用于运行 Zsh 辅助脚本和部分 Neovim 工具。只有需要 [.config/mise/config.toml](.config/mise/config.toml) 中的完整开发工具链时，才执行 `mise install`

### 7. 安装 tmux 插件

```bash
./one-click-config/setup-tmux.sh
```

请用普通用户执行。脚本会安装 TPM、会话恢复和状态栏等 tmux 插件

### 8. 启动工作区

```bash
exec zsh
tmux new-session -A
```

现在可以运行 `nvim` 打开编辑器。第一次启动时，Neovim 会自动下载插件

第一次使用 tmux？阅读 [Tmux 快捷键指南](https://github.com/beixiyo/dotfiles/wiki/tmux-guide-keymaps)，了解 window、pane、复制模式和会话恢复

第一次使用 Neovim？从 [模式与移动](https://github.com/beixiyo/dotfiles/wiki/nvim-learn-01-modes-and-movement)开始，再按顺序学习[编辑与文本对象](https://github.com/beixiyo/dotfiles/wiki/nvim-learn-02-editing-and-text-objects)和[高级命令](https://github.com/beixiyo/dotfiles/wiki/nvim-learn-03-advanced-commands)

> 只想复制配置文件、不安装依赖或修改系统？查看 [one-click-config 说明](one-click-config/README.md)中的手动部署方式

## 为什么选择全终端工作流

- **轻量且适合远程开发**：只需要 SSH，不必传输完整桌面画面，也不依赖 RDP、Sunshine 或 NoMachine；网络波动时，终端通常比图形桌面更容易保持可用
- **工作状态可以恢复**：[tmux](https://github.com/tmux/tmux) 会在 SSH 断开后继续保持窗口、分屏和正在运行的 CLI。tmux-resurrect 与 tmux-continuum 还能定期保存布局、目录、pane 内容和部分启动命令，在重启后重建工作区
- **支持临时协作**：同一 Unix 账户下的多个 SSH 客户端可以连接同一个 tmux 会话，看到相同的输入输出。由于焦点和输入状态也完全共享，这种方式更适合短时间、协商好的协作
- **编辑器完全可编程**：[Neovim](https://neovim.io/) 是最自由、也最活跃的编辑器之一。配置本身就是 Lua 程序，插件可以直接放在本地或发布到 GitHub，不必经过插件市场；主要代价是 Lua 的语法和开发体验并不算出色
- **需要时也有流畅 GUI**：[Neovide](https://neovide.dev/) 可以在保留完整 Neovim 工作流的同时，提供更流畅的动画、滚动和图形界面

### 开发运行时

开发语言和运行时统一交给 [mise](https://mise.jdx.dev/) 管理。它可以在一份配置中声明 Bun、Node.js、Python、Go、Rust 等大部分常用运行时及其版本；`mise install` 可以一次安装全部配置。本仓库自身只需要 Bun：

```bash
# 本仓库只需要 Bun
mise use -g bun
```

需要完整开发环境时再执行 `mise install`。进入不同项目时，mise 会根据项目配置自动选择对应版本，不需要手动修改 PATH。本仓库的 [mise 配置](.config/mise/config.toml) 默认选择 Node.js 22、最新版 Bun / Go / Python 和 stable Rust；Git、tmux、编译器等系统级工具仍由 Homebrew、pacman 或 apt 等系统包管理器安装

## AI 工作流

- `tmux` 让长时间运行的 AI CLI 在 SSH 断开后继续保持；电脑重启后，resurrect / continuum 可以重建已保存的布局，并重新启动配置过的 AI CLI
- `<leader>ts` 会把当前代码片段或整行，以及相关诊断信息，直接送到旁边的 AI 面板
- `nvd` 会把当前目录和分屏布局交给 Neovide，退出后再恢复到原来的 tmux pane
- `vv-mcp` 与 LSP、tmux 协作，让代码上下文可以在编辑器、Shell 和 AI 工具之间流转

## 终端操作

终端配置支持两种可以切换的布局模式

**pane** 是一个分屏区域，**tab/window** 用于容纳一组分屏。下面的快捷键在 Neovim、tmux 和终端裸模式中保持一致，不需要为每个工具分别记忆一套导航方式

**分屏**

- **`Ctrl + Alt + h/j/k/l`** — 向左 / 下 / 上 / 右移动焦点
- **`Ctrl + Alt + 左/右/上/下`** — 调整当前 pane 或编辑器窗口大小
- **`Ctrl + Alt + -`** / **`Ctrl + Alt + \`** — 创建纵向 / 横向分屏
- **`Ctrl + Alt + w`** — 关闭当前 pane
- **`Ctrl + Alt + b`** — 放大或恢复当前 pane

**标签页与窗口**

- **`Ctrl + Shift + t`** / **`Ctrl + Shift + w`** — 新建 / 关闭窗口
- **`Ctrl + 1`** … **`Ctrl + 8`** — 切换到第 1 … 8 个窗口

Kitty、Ghostty 和 WezTerm 都分别提供了 tmux 与裸 / 原生模式的快捷键配置。快捷键保持一致，只有底层管理者不同。需要切换模式时，在对应终端配置中保留一种模式的 `include` / `config-file`，并注释掉另一种；两种模式不能同时启用。当前 Kitty 默认使用 tmux 模式，通常用 `tmux new-session -A` 启动或接入主会话

## 技术栈

| 层级 | 选择 | 说明 |
|---|---|---|
| 系统 | [Arch Linux](https://archlinux.org/) + [Niri](https://github.com/niri-wm/niri) | 我的基础桌面栈 |
| Shell | [Zsh](https://www.zsh.org/) | 和 Bash 足够接近，AI 生成的 shell 片段更不容易写错 |
| 终端复用器 | [tmux](https://github.com/tmux/tmux) | 默认会话层，轻量、稳定、可定制 |
| 终端 | [Kitty](https://sw.kovidgoyal.net/kitty/) | 主力终端；扩展性最强，原生模式可实现接近 tmux 的完整工作流，并支持平滑光标 |
| 终端 | [Ghostty](https://ghostty.org/) | 支持自定义 shader，内存占用略高 |
| 终端 | [WezTerm](https://wezterm.org/) | 使用 Lua 配置的跨平台中庸之选，尤其适合 Windows |
| 文件管理器 | [Yazi](https://yazi-rs.github.io/) | 在终端中快速浏览和管理文件与目录 |
| 编辑器 | [Neovim](https://neovim.io/) | 用于代码、Git、笔记和工作流的主力编辑器 |

## Neovim

Neovim 是我的主力编辑器，主要处理代码、Git、笔记和编辑器内自动化
vv-* 插件覆盖导航、Git、搜索、重构、Markdown 和工作流面板

### Neovide 与 `nvd`

[Neovide](https://neovide.dev/) 是 Neovim 的 GPU 加速 GUI 前端，支持平滑滚动，也是全世界最流畅的编辑器

`nvd` 在当前目录或指定项目目录启动 Neovide。处于 tmux 中时，它会保留并恢复原来的 window 或 pane 布局；在 Kitty 裸模式下通过 Kitty remote control 交接，并尽可能恢复源 window；其他情况则直接启动 Neovide

### 插件

| 分组 | 插件 |
|---|---|
| 基础 | [vv-utils](https://github.com/beixiyo/vv-utils.nvim) · [vv-icons](https://github.com/beixiyo/vv-icons.nvim) · [vv-dashboard](https://github.com/beixiyo/vv-dashboard.nvim) · [vv-statuscol](https://github.com/beixiyo/vv-statuscol.nvim) · [vv-indent](https://github.com/beixiyo/vv-indent.nvim) |
| Git 和文件 | [vv-git](https://github.com/beixiyo/vv-git.nvim) · [vv-explorer](https://github.com/beixiyo/vv-explorer.nvim) · [vv-bufferline](https://github.com/beixiyo/vv-bufferline.nvim) · [vv-scrollbar](https://github.com/beixiyo/vv-scrollbar.nvim) · [vv-hover](https://github.com/beixiyo/vv-hover.nvim) |
| 编辑 | [vv-expand](https://github.com/beixiyo/vv-expand.nvim) · [vv-markdown](https://github.com/beixiyo/vv-markdown.nvim) · [vv-replace](https://github.com/beixiyo/vv-replace.nvim) |
| 工作流 | [vv-flow](https://github.com/beixiyo/vv-flow.nvim) · [vv-task-panel](https://github.com/beixiyo/vv-task-panel.nvim) · [vv-i18n](https://github.com/beixiyo/vv-i18n.nvim) · [vv-log-hl](https://github.com/beixiyo/vv-log-hl.nvim) · [vv-mcp](https://github.com/beixiyo/vv-mcp.nvim) |

每个插件仓库都有独立的中英 README；[Neovim 配置文档](.config/nvim/README.md) 提供了可点击的插件演示图集

## 模块

| 模块 | 路径 | 文档 |
|---|---|---|
| Zsh | `~/.zsh/` | [Wiki](https://github.com/beixiyo/dotfiles/wiki/zsh-guide-shell) · [说明](.zsh/README.md) · [开发指南](.zsh/AGENTS.md) |
| Neovim | `~/.config/nvim/` | [Wiki](https://github.com/beixiyo/dotfiles/wiki) · [说明](.config/nvim/README.md) · [开发指南](.config/nvim/AGENTS.md) |
| Tmux | `~/.config/tmux/` | [Wiki](https://github.com/beixiyo/dotfiles/wiki/tmux-guide-keymaps) · [说明](.config/tmux/README.md) |
| 终端 | `~/.config/{kitty,ghostty,wezterm}/` | [Wiki](https://github.com/beixiyo/dotfiles/wiki/terminal-guide-keymaps) |
| Yazi | `~/.config/yazi/` | [Wiki](https://github.com/beixiyo/dotfiles/wiki/yazi-guide-keymaps) |
| Niri | `~/.config/niri/` | [Wiki](https://github.com/beixiyo/dotfiles/wiki/niri-guide-usage) |
| Karabiner | `~/.config/karabiner/` | [Wiki](https://github.com/beixiyo/dotfiles/wiki/karabiner-guide-windows-keymap) |
| 剪贴板 | `~/.config/quickshell/clipboard/` | [Wiki](https://github.com/beixiyo/dotfiles/wiki/linux-guide-clipboard) |
| 安装脚本 | `one-click-config/` | [说明](one-click-config/README.md) |

完整架构图见 [AGENTS.md](AGENTS.md)
