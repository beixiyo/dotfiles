# dotfiles

> A lightweight, recoverable terminal workspace built for remote development

<p align="center">English | <a href="README.zh-CN.md">中文</a></p>

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

<video muted autoplay loop controls src="https://github.com/user-attachments/assets/b26a9b91-1898-4fcb-99b3-692911eb10ed" title="Terminal workflow demo"></video>

<p align="center"><strong>Neovim setup and plugin showcase: <a href=".config/nvim/README.md">Chinese guide →</a></strong></p>

This repository turns a fresh terminal into a complete development workspace: Zsh provides the shell, tmux keeps sessions alive, Kitty / Ghostty / WezTerm render the terminal, and Neovim handles code, Git, notes, and AI-assisted workflows. The same shortcuts move between terminal panes and editor splits, so the tools feel like one environment instead of several unrelated apps

<!--toc:start-->
- [dotfiles](#dotfiles)
  - [Guides and documentation](#guides-and-documentation)
  - [Start here: setup](#start-here-setup)
  - [Why a terminal-first workflow](#why-a-terminal-first-workflow)
    - [Development runtimes](#development-runtimes)
  - [AI workflow](#ai-workflow)
  - [Terminal workflow](#terminal-workflow)
  - [Stack](#stack)
  - [Neovim](#neovim)
    - [Neovide and `nvd`](#neovide-and-nvd)
    - [Plugins](#plugins)
  - [Modules](#modules)
<!--toc:end-->

## Guides and documentation

The [GitHub Wiki](https://github.com/beixiyo/dotfiles/wiki) contains the detailed Chinese usage guides. Start with the workflow you need instead of reading the repository from top to bottom:

| Topic | Guides |
|---|---|
| Neovim basics | [Modes and Movement](https://github.com/beixiyo/dotfiles/wiki/nvim-learn-01-modes-and-movement) · [Editing and Text Objects](https://github.com/beixiyo/dotfiles/wiki/nvim-learn-02-editing-and-text-objects) · [Advanced Commands](https://github.com/beixiyo/dotfiles/wiki/nvim-learn-03-advanced-commands) |
| Neovim workflow | [Shortcut Tips](https://github.com/beixiyo/dotfiles/wiki/nvim-guide-shortcut-tips) · [DAP Debugging](https://github.com/beixiyo/dotfiles/wiki/nvim-debug-dap) · [Lua Configuration](https://github.com/beixiyo/dotfiles/wiki/nvim-config-lua) |
| Shell and terminal | [Zsh](https://github.com/beixiyo/dotfiles/wiki/zsh-guide-shell) · [Tmux](https://github.com/beixiyo/dotfiles/wiki/tmux-guide-keymaps) · [Terminal Keymaps](https://github.com/beixiyo/dotfiles/wiki/terminal-guide-keymaps) · [Yazi](https://github.com/beixiyo/dotfiles/wiki/yazi-guide-keymaps) |
| Desktop environment | [Niri](https://github.com/beixiyo/dotfiles/wiki/niri-guide-usage) · [Karabiner Windows Keymap](https://github.com/beixiyo/dotfiles/wiki/karabiner-guide-windows-keymap) · [Linux Clipboard History](https://github.com/beixiyo/dotfiles/wiki/linux-guide-clipboard) |
| Neovim development | [Lua for TypeScript Developers](https://github.com/beixiyo/dotfiles/wiki/nvim-dev-lua-for-ts-devs) · [Neovim API](https://github.com/beixiyo/dotfiles/wiki/nvim-dev-api) · [Plugin Paths](https://github.com/beixiyo/dotfiles/wiki/nvim-config-plugin-paths) |

## Start here: setup

No terminal experience is required. Complete these steps in order and move on only when the current step works

### 1. Choose a modern terminal

Choose one of the following terminals. They all support this configuration, and **only one is required**:

- [Kitty](https://sw.kovidgoyal.net/kitty/) — **the most extensible and recommended choice**. Of the three terminals, only Kitty's native mode reproduces the full tmux-like window, pane, and layout handoff workflow, and it supports a smooth cursor
- [Ghostty](https://ghostty.org/) — supports custom shaders for terminal visual effects; its feature set is more direct and its memory usage is slightly higher
- [WezTerm](https://wezterm.org/) — a balanced cross-platform choice for macOS, Linux, and Windows, configured through Lua scripts

The setup scripts support macOS and mainstream Linux distributions. Windows users can install WezTerm, but should deploy the shell configuration inside [WSL](https://learn.microsoft.com/windows/wsl/install)

### 2. Check for a Nerd Font

A Nerd Font provides the folder, Git, diagnostic, and interface icons used by the terminal, Neovim, and prompt. **Skip this step if a Nerd Font is already installed and selected in the terminal**

[Maple Mono NF](https://github.com/subframe7536/maple-font/releases) is recommended, or choose another font from [Nerd Fonts](https://www.nerdfonts.com/font-downloads). After installing it, select that Nerd Font in the terminal settings

On Linux, the upstream Maple Mono NF package avoids downloading the much larger AUR split-package source:

The command below requires `curl` and `unzip`. If they are not installed yet, use the browser to install the font or return here after step 4

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

### 3. Clone the repository

Make sure Git is installed. On a fresh system, run the command for the current platform:

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

Then clone the repository and enter it:

```bash
git clone https://github.com/beixiyo/dotfiles.git ~/dotfiles
cd ~/dotfiles
```

Run all following `./one-click-config/...` commands from `~/dotfiles`

### 4. Install command-line dependencies

```bash
./one-click-config/setup-deps.sh
```

The script detects pacman, apt, dnf, zypper, or Homebrew and installs Zsh, Neovim, tmux, mise, Git, ripgrep, fd, and related tools. Administrator access is requested only when system packages actually need to be installed

### 5. Deploy the configuration

Most users only need the first command:

```bash
# Deploy to the current user
./one-click-config/setup-user.sh

# Optional: deploy to specific users
./one-click-config/setup-user.sh alice bob
```

With no arguments, the script deploys to the current user and asks whether to configure anyone else. Passing `alice bob` deploys to those users. Linux can create missing users automatically; on macOS, create them in System Settings first

Before replacing existing files, the script asks for confirmation and can back them up under `~/.dotfiles-backup-<timestamp>/`. Administrator access is limited to required operations such as creating users, changing login shells, and configuring sudo

### 6. Install Bun

```bash
# This repository only requires Bun
mise use -g bun
```

Bun runs the Zsh helpers and parts of the Neovim tooling. Run `mise install` only when the complete toolchain in [.config/mise/config.toml](.config/mise/config.toml) is wanted

### 7. Install tmux plugins

```bash
./one-click-config/setup-tmux.sh
```

Run this as the normal user. It installs TPM, session recovery, status-line, and related tmux plugins

### 8. Start the workspace

```bash
exec zsh
tmux new-session -A
```

Run `nvim` to open the editor. Neovim downloads its plugins automatically on the first launch

New to tmux? Read the [Tmux keymap guide](https://github.com/beixiyo/dotfiles/wiki/tmux-guide-keymaps) for windows, panes, copy mode, and workspace recovery

New to Neovim? Follow the Wiki in order: [Modes and Movement](https://github.com/beixiyo/dotfiles/wiki/nvim-learn-01-modes-and-movement), [Editing and Text Objects](https://github.com/beixiyo/dotfiles/wiki/nvim-learn-02-editing-and-text-objects), then [Advanced Commands](https://github.com/beixiyo/dotfiles/wiki/nvim-learn-03-advanced-commands)

> Want configuration files only, without installing dependencies or changing the system? See the manual deployment option in the [one-click-config guide](one-click-config/README.md)

## Why a terminal-first workflow

- **Lightweight and remote-friendly**: SSH is all you need. There is no full desktop stream and no dependency on RDP, Sunshine, or NoMachine; a terminal also remains more usable when the network becomes unstable
- **Recoverable workspace**: [tmux](https://github.com/tmux/tmux) keeps windows, panes, and CLIs alive across SSH disconnects. tmux-resurrect and tmux-continuum periodically save layouts, directories, pane contents, and selected commands so the workspace can be reconstructed after a reboot
- **Quick collaboration**: multiple SSH clients using the same Unix account can attach to one tmux session and share its input and output. Because focus and input state are shared too, this works best for short, coordinated sessions
- **A fully programmable editor**: [Neovim](https://neovim.io/) is one of the freest and most active editors available. Its configuration is a Lua program, and plugins can live locally or be published directly on GitHub without a marketplace; the main trade-off is Lua's less pleasant syntax and developer experience
- **A smooth GUI when wanted**: [Neovide](https://neovide.dev/) adds fluid animation, scrolling, and a graphical frontend without giving up the Neovim workflow

### Development runtimes

[mise](https://mise.jdx.dev/) manages development languages and runtimes in one place. A single configuration can declare Bun, Node.js, Python, Go, Rust, and most other common runtimes; `mise install` installs the complete configured toolchain. This repository itself only requires Bun:

```bash
# This repository only requires Bun
mise use -g bun
```

Run `mise install` only when the complete development toolchain is wanted. mise automatically selects configured versions when entering a project, without manual PATH changes. This repository's [mise configuration](.config/mise/config.toml) selects Node.js 22, the latest Bun / Go / Python, and stable Rust. System-level tools such as Git, tmux, and compilers still come from Homebrew, pacman, apt, or another system package manager

## AI workflow

- `tmux` keeps long-running AI CLIs alive across SSH disconnects; after a reboot, resurrect / continuum can rebuild the saved layout and restart configured AI CLIs
- `<leader>ts` sends the current code selection or line, plus diagnostics, to the AI pane next door
- `nvd` hands the current directory and split layout to Neovide, then restores the original tmux pane on exit
- `vv-mcp` works with LSP and tmux so code context can move between the editor, the shell, and AI tools

## Terminal workflow

The terminal configs support two interchangeable layouts

A **pane** is one split area. A **tab/window** groups one or more panes. These shortcuts stay consistent across Neovim, tmux, and the terminal's native mode, so you do not need to learn a separate navigation scheme for each tool

**Panes**

- **`Ctrl + Alt + h/j/k/l`** — move focus left / down / up / right
- **`Ctrl + Alt + Left/Right/Up/Down`** — resize the current pane or editor split
- **`Ctrl + Alt + -`** / **`Ctrl + Alt + \`** — create a vertical / horizontal split
- **`Ctrl + Alt + w`** — close the current pane
- **`Ctrl + Alt + b`** — zoom or restore the current pane

**Tabs and windows**

- **`Ctrl + Shift + t`** / **`Ctrl + Shift + w`** — create / close a window
- **`Ctrl + 1`** … **`Ctrl + 8`** — switch to window 1 … 8

Kitty, Ghostty, and WezTerm all have tmux and standalone/native keymap files. The shortcuts stay the same; only the backend changes. Enable exactly one mode in the relevant terminal config by keeping its `include` / `config-file` line active and commenting out the other. The default Kitty setup is tmux-first; in tmux mode, start or attach with `tmux new-session -A`

## Stack

| Layer | Choice | Notes |
|---|---|---|
| System | [Arch Linux](https://archlinux.org/) + [Niri](https://github.com/niri-wm/niri) | My base desktop stack |
| Shell | [Zsh](https://www.zsh.org/) | Close enough to Bash that AI-written shell snippets are less likely to drift |
| Multiplexer | [tmux](https://github.com/tmux/tmux) | Default session layer, lightweight and stable |
| Terminal | [Kitty](https://sw.kovidgoyal.net/kitty/) | Primary terminal; the most extensible, with a complete tmux-like native workflow and smooth cursor support |
| Terminal | [Ghostty](https://ghostty.org/) | Custom shader support with slightly higher memory usage |
| Terminal | [WezTerm](https://wezterm.org/) | A balanced cross-platform option configured in Lua, especially useful on Windows |
| File manager | [Yazi](https://yazi-rs.github.io/) | Fast file and directory browsing inside the terminal |
| Editor | [Neovim](https://neovim.io/) | Main editor for code, Git work, notes, and workflow |

## Neovim

Neovim is my main editor for code, Git work, notes, and in-editor automation
The vv-* plugins cover navigation, Git, search, refactors, Markdown, and workflow panels

### Neovide and `nvd`

[Neovide](https://neovide.dev/) is Neovim's GPU-accelerated GUI frontend with smooth scrolling, and the smoothest editor in the world

`nvd` launches Neovide in the current or specified project directory. Inside tmux, it preserves and restores the original window or pane layout; in Kitty native mode, it hands off through Kitty remote control and restores the source window as closely as possible; otherwise, it launches Neovide directly

### Plugins

| Group | Plugins |
|---|---|
| Foundation | [vv-utils](https://github.com/beixiyo/vv-utils.nvim) · [vv-icons](https://github.com/beixiyo/vv-icons.nvim) · [vv-dashboard](https://github.com/beixiyo/vv-dashboard.nvim) · [vv-statuscol](https://github.com/beixiyo/vv-statuscol.nvim) · [vv-indent](https://github.com/beixiyo/vv-indent.nvim) |
| Git and files | [vv-git](https://github.com/beixiyo/vv-git.nvim) · [vv-explorer](https://github.com/beixiyo/vv-explorer.nvim) · [vv-bufferline](https://github.com/beixiyo/vv-bufferline.nvim) · [vv-scrollbar](https://github.com/beixiyo/vv-scrollbar.nvim) · [vv-hover](https://github.com/beixiyo/vv-hover.nvim) |
| Editing | [vv-expand](https://github.com/beixiyo/vv-expand.nvim) · [vv-markdown](https://github.com/beixiyo/vv-markdown.nvim) · [vv-replace](https://github.com/beixiyo/vv-replace.nvim) |
| Workflow | [vv-flow](https://github.com/beixiyo/vv-flow.nvim) · [vv-task-panel](https://github.com/beixiyo/vv-task-panel.nvim) · [vv-i18n](https://github.com/beixiyo/vv-i18n.nvim) · [vv-log-hl](https://github.com/beixiyo/vv-log-hl.nvim) · [vv-mcp](https://github.com/beixiyo/vv-mcp.nvim) |

Each plugin repository has its own bilingual README. The [Neovim guide (Chinese)](.config/nvim/README.md) includes a clickable plugin demo gallery

## Modules

| Module | Path | Docs |
|---|---|---|
| Zsh | `~/.zsh/` | [Wiki](https://github.com/beixiyo/dotfiles/wiki/zsh-guide-shell) · [README](.zsh/README.md) · [Dev guide](.zsh/AGENTS.md) |
| Neovim | `~/.config/nvim/` | [Wiki](https://github.com/beixiyo/dotfiles/wiki) · [README (Chinese)](.config/nvim/README.md) · [Dev guide](.config/nvim/AGENTS.md) |
| Tmux | `~/.config/tmux/` | [Wiki](https://github.com/beixiyo/dotfiles/wiki/tmux-guide-keymaps) · [README](.config/tmux/README.md) |
| Terminals | `~/.config/{kitty,ghostty,wezterm}/` | [Wiki](https://github.com/beixiyo/dotfiles/wiki/terminal-guide-keymaps) |
| Yazi | `~/.config/yazi/` | [Wiki](https://github.com/beixiyo/dotfiles/wiki/yazi-guide-keymaps) |
| Niri | `~/.config/niri/` | [Wiki](https://github.com/beixiyo/dotfiles/wiki/niri-guide-usage) |
| Karabiner | `~/.config/karabiner/` | [Wiki](https://github.com/beixiyo/dotfiles/wiki/karabiner-guide-windows-keymap) |
| Clipboard | `~/.config/quickshell/clipboard/` | [Wiki](https://github.com/beixiyo/dotfiles/wiki/linux-guide-clipboard) |
| Setup scripts | `one-click-config/` | [README](one-click-config/README.md) |

See [AGENTS.md](AGENTS.md) for the full architecture map
