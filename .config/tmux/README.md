# TMUX

当前项目设置 Prefix = `C-Space`（即 `Ctrl + Space`）

## 安装

```bash
# macOS
brew install tmux

# Arch / Manjaro
sudo pacman -S --needed tmux

# Ubuntu / Debian
sudo apt install -y tmux

# Fedora
sudo dnf install -y tmux

# Alpine
sudo apk add tmux
```

克隆 tpm 及安装插件：

dotfiles 已部署时，优先在仓库的 `one-click-config/` 目录执行：

```bash
./setup-tmux.sh
```

脚本会在独立 tmux socket 中克隆 TPM 并安装全部已声明插件，不会影响当前 tmux server。下面是用于排障的手动安装方式：

```bash
# 1. 克隆 tpm
git clone --depth=1 --single-branch https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm

# 2. 启动一次 tmux（让 tmux 读取配置，识别插件列表）
tmux

# 3. 退出 tmux 后安装插件（或在 tmux 内按 prefix+I）
~/.config/tmux/plugins/tpm/bin/install_plugins
```

---

## 核心概念

```
tmux server（后台守护进程）
  └── session（会话，关闭终端不丢失）
        └── window（窗口，类似浏览器 tab）
              └── pane（面板，窗口内的分割）
```

- **终端窗口只是 client**，关掉终端 ≠ 关掉 session
- 多个终端可以同时 attach 到同一个 session（镜像同步）
- 启动交互式 Zsh 且当前不在 tmux 或 IDE 内嵌终端时，会显示 tmux 入口：`a` attach 已有 session，`n` 新建 session，Enter 或其他键跳过

---

## Session 管理

| 操作 | 命令 / 快捷键 |
|------|--------------|
| 列出所有 session | `tmux ls` |
| 新建 session | `tmux new-session -s <name>` |
| Attach 到 session | `tmux attach -t <name>` |
| **Detach（保留 session）** | `Prefix d` |
| 交互式切换 session | `Prefix s` |
| 重命名当前 session | `Prefix $` |
| 销毁指定 session | `tmux kill-session -t <name>` |
| 销毁除当前外所有 session | `tmux kill-session -a` |
| 销毁所有 session（含 server） | `tmux kill-server` |

> Zsh 入口不会固定创建 `main` session。存在一个 session 时按 `a` 直接 attach；存在多个 session 时按 `a` 后选择编号；按 `n` 可输入名称，留空则由 tmux 自动编号

---

## 会话保存与恢复

当前配置使用 `tmux-resurrect` 和 `tmux-continuum`：

- `Prefix Ctrl+S`：手动保存 session、window、pane、布局、目录和 pane 输出
- `Prefix Ctrl+R`：手动恢复最近一次保存
- 每 15 分钟自动保存
- tmux server 启动时自动恢复最近一次环境
- Neovim 使用 session 策略恢复
- Claude、Codex 和 OpenCode 会改写为各自的继续会话命令

关闭终端但 tmux server 仍运行时，只需重新 attach；tmux server 或机器重启后的恢复才由 resurrect / continuum 负责。恢复会重建布局并重新运行配置过的命令，不会让关机前的原进程跨重启继续存活

---

## Window 管理（无 Prefix，对齐终端 tab 习惯）

| 操作 | 快捷键 |
|------|--------|
| 新建 window | `Ctrl+Shift+T` |
| 关闭 window | `Ctrl+Shift+W` |
| 切换到第 N 个 window | `Ctrl+1` … `Ctrl+8` |
| 重命名 window | `Prefix ,` |
| 下一个 window | `Prefix n` |
| 上一个 window | `Prefix p` |

---

## Pane 管理（无 Prefix，`Ctrl+Alt+*`）

| 操作 | 快捷键 |
|------|--------|
| 垂直分割（左右） | `Ctrl+Alt+\` |
| 水平分割（上下） | `Ctrl+Alt+-` |
| 关闭 pane | `Ctrl+Alt+W` |
| 全屏或恢复当前 pane | `Ctrl+Alt+B` |
| 焦点左/下/上/右 | `Ctrl+Alt+H/J/K/L` |
| 调整 pane 大小 | `Ctrl+Alt+←↓↑→` |
| 右键 | 直接粘贴剪贴板 |

> **Neovim 透传**：pane 内运行 nvim 时，`Ctrl+Alt+H/J/K/L` 会透传给 nvim（smart-splits），实现 nvim split 和 tmux pane 无缝导航

---

## Copy Mode（vi 风格）

| 操作 | 快捷键 |
|------|--------|
| 进入 copy mode | `Prefix v` |
| 开始选择 | `v` |
| 矩形选择 | `Ctrl+V` |
| 复制选中 | `y` |
| 复制到行尾 | `Y` |
| 退出 | `q` 或 `Esc` |

copy mode 内同样可用 `Ctrl+Alt+H/J/K/L` 切换 pane，不会卡死

---

## 配置管理

| 操作 | 命令 / 快捷键 |
|------|--------------|
| 重载配置 | `Prefix r` |
| 安装插件 | `Prefix I`（大写） |
| 更新插件 | `Prefix U` |
| 卸载多余插件 | `Prefix Alt+U` |

配置入口：`~/.config/tmux/tmux.conf`，模块放在 `conf/`

---

## Status Bar

右侧显示：**session 名 · CPU · RAM · 网速**

网速仅在上行或下行超过 **30 KB/s** 时才出现，平时静默

---

## 文件结构

```
tmux.conf          入口，source 所有模块
conf/
  options.conf     基础选项（prefix、颜色、鼠标、编号）
  window.conf      window 快捷键
  pane.conf        pane 分割、导航、调整大小
  copy-mode.conf   vi copy mode
  plugins.conf     tpm 插件列表及安装说明
  status.conf      status bar 布局
scripts/
  net_speed.sh     网速计算脚本（macOS / Linux 双支持）
```
