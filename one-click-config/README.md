# 一键配置部署

用于在新机器或新用户下部署 dotfiles、安装基础工具，并按需配置 tmux、桌面环境和系统权限

## 推荐安装流程

```bash
git clone --depth=1 --single-branch --no-tags \
  https://github.com/beixiyo/dotfiles.git /tmp/dotfiles

cd /tmp/dotfiles/one-click-config

./setup-deps.sh
./setup-user.sh
# 本仓库只需要 Bun
mise use -g bun
./setup-tmux.sh
```

完整流程包含：

1. 安装基础命令行工具
2. 部署 dotfiles 到当前用户
3. 安装 [Maple Mono NF](../README.zh-CN.md#安装) 或其他 Nerd Font；字体不会由 `setup-deps.sh` 自动安装
4. 通过 `mise use -g bun` 安装本仓库需要的 Bun；需要完整工具链时再执行 `mise install`
5. 安装 TPM 和 tmux 插件

## 部署用户配置

### `setup-user.sh` 做什么

脚本会：

1. 检查 Git，并在缺失时要求安装
2. 检查 Zsh 和 Starship；缺失时询问是否安装，允许跳过
3. 使用当前仓库作为配置源；不在仓库内运行时从 GitHub clone
4. 按顶层文件和 `.config` 子目录交互确认覆盖
5. 可选地把旧配置备份到 `~/.dotfiles-backup-<timestamp>/`
6. 尝试把目标用户的默认 Shell 设置为 Zsh
7. 将目标用户加入 `admin`、`sudo` 或 `wheel` 组
8. 为当前系统存在的包管理器配置有限的 NOPASSWD 路径
9. 最后单独询问是否把用户配置链接到 `/root`

不传用户时，默认处理当前用户，然后询问是否额外创建用户：

```bash
./setup-user.sh
```

传入用户名时，只处理指定用户；可以一次处理多个：

```bash
./setup-user.sh alice
./setup-user.sh alice bob
```

系统提供 `useradd` 时可以自动创建缺失用户；macOS 需要先在“系统设置”中创建账户。部署配置文件本身不需要 root；配置 sudo 组、修改登录 Shell、创建其他用户和链接 `/root` 时会单独请求管理员权限。只想复制配置且不配置系统权限时，请使用根 README 中的“只复制配置文件”方式

### 覆盖与备份

- 默认不会静默覆盖现有配置
- 每个顶层项目会询问 `overwrite? [y/N/a=all]`
- `.config` 会按 `nvim`、`tmux`、`kitty` 等子目录分别询问
- 覆盖前可以创建一次性备份
- 上游已经删除的文件不会自动从用户目录删除
- `/root` 下已存在真实文件或目录时会跳过，不会强制覆盖
- 拒绝 `/root` 链接后不会对 `/root` 做任何写入

## 安装基础依赖

```bash
./setup-deps.sh
```

脚本会检测现有包管理器，跳过已经存在的命令，并在安装系统包时按需请求管理员权限

支持：

- Arch：paru、yay、pacman
- Debian / Ubuntu：apt、apt-get
- Fedora / RHEL：dnf、yum
- openSUSE：zypper
- macOS / Linuxbrew：Homebrew

paru、yay 和 Homebrew 始终以普通用户身份运行。apt 安装的 `fd-find` 和 `bat` 会按需创建 `fd`、`bat` 兼容链接

只有发现缺失的系统软件包时才会同步包管理器。Arch 为避免 partial upgrade，会在首次安装前执行一次 `paru -Syu`、`yay -Syu` 或 `pacman -Syu`；这会同时升级当前系统

### 自动尝试安装的工具

| 工具 | 主要用途 |
|---|---|
| Git、curl、wget、aria2 | 仓库与下载 |
| Zsh、Starship | Shell 与提示符 |
| Fzf、fd、ripgrep | 文件、内容和交互式搜索 |
| lsd、tree、bat | 文件列表与预览 |
| delta | Git diff 预览 |
| zoxide | 智能目录跳转 |
| btop | 系统监控 |
| jq | JSON 处理 |
| Neovim | 编辑器 |
| tmux | 终端复用器 |
| mise | 工具链版本管理 |
| safe-rm | 可选的安全删除包装 |
| unzip、7z、unrar | 压缩文件处理 |
| wl-clipboard | Wayland 剪贴板 |

脚本会按当前包管理器尝试安装这些工具。当前平台没有对应包、官方脚本失败或安装后命令不在 PATH 时，会在最终摘要中列为需要手动处理

### 额外运行时与功能依赖

`setup-deps.sh` 不负责所有平台或硬件相关软件。按使用的功能补充安装：

| 功能 | 额外依赖 | 安装建议 |
|---|---|---|
| Zsh 的 `d / b / i / t / ff / fs / fp / dd` 等高级命令 | Bun | 部署配置后执行 `mise use -g bun` |
| `fp`、`ports` 的端口识别 | `lsof` | 使用系统包管理器安装 |
| Docker 面板 `dd` | Docker CLI 与 daemon | 安装 Docker Desktop 或系统 Docker |
| Yazi 文件管理 | Yazi | 使用 mise 或系统包管理器安装 |
| Neovim Tree-sitter | C 编译器、`tree-sitter-cli >= 0.26.1` | 优先系统包管理器；版本过低时使用 Cargo |
| VS Code 打开操作 | `code` CLI | 在 VS Code 中安装 Shell Command |

Zsh 各命令的具体功能见 [.zsh/README.md](../.zsh/README.md)

## 安装 tmux 插件

tmux 插件目录不会提交到 Git，新机器部署后需要执行：

```bash
./setup-tmux.sh
```

更新全部插件：

```bash
./setup-tmux.sh --update
```

脚本会在独立 tmux socket 中运行 TPM，不会干扰当前正在使用的 tmux server。请使用普通用户执行，否则插件会安装到 `/root`

## 可选系统脚本

这些脚本不是通用安装流程的一部分，只在对应平台使用：

| 脚本 | 平台 | 作用 |
|---|---|---|
| `setup-sudoers.sh` | Linux / macOS | 查看并交互管理 NOPASSWD 命令白名单 |
| `setup-kde.sh` | Arch + KDE Plasma 6 | 安装 MacTahoe 主题、图标和桌面特效 |
| `setup-niri.sh` | Arch | 安装 Niri、Wayland 桌面组件和中文 locale |
| `setup-nvidia.sh` | Arch + NVIDIA | 检测显卡并安装驱动、配置 initramfs 和 Wayland |

示例：

```bash
./setup-sudoers.sh --list
./setup-sudoers.sh docker systemctl

./setup-kde.sh --deps
./setup-niri.sh
sudo ./setup-nvidia.sh
```

`setup-sudoers.sh` 中部分候选命令可以间接获得 root Shell。启用前必须阅读脚本输出的安全提示，不要把不信任的本地用户加入对应 sudo 组

## 权限边界

- 配置文件复制本身不使用 root；sudo 组、登录 Shell、其他用户和 `/root` 链接会按步骤提权
- 系统包索引和系统包安装按需使用 sudo
- paru、yay、Homebrew 不以 root 运行
- 只为包管理器的绝对路径配置 NOPASSWD，不会加入编辑器、Shell、Git、SSH 等危险命令
- sudoers 内容写入 `/etc/sudoers.d/oneclickconfig-nopasswd` 前会通过 `visudo` 校验
- `/root` 链接是独立的可选步骤
- `setup-nvidia.sh` 明确要求 root，其它脚本按具体操作请求权限

## 测试

权限与部署测试运行在一次性 Docker 容器中，不会修改宿主机用户、`/root` 或 `/etc/sudoers*`：

```bash
./tests/run.sh
```

测试覆盖普通用户部署、覆盖与备份、sudoers 权限边界、`/root` 链接和多发行版系统行为

## 文件结构

```text
one-click-config/
├── setup-user.sh          # 部署 dotfiles 到一个或多个用户
├── setup-deps.sh          # 安装基础命令行工具
├── setup-tmux.sh          # 安装或更新 TPM 插件
├── setup-sudoers.sh       # 管理 NOPASSWD 命令白名单
├── setup-kde.sh           # KDE 主题与桌面环境
├── setup-niri.sh          # Niri 桌面环境
├── setup-nvidia.sh        # NVIDIA 驱动与 Wayland 配置
├── lib/
│   ├── common.sh          # 日志、颜色与权限辅助
│   ├── packages.sh        # 包管理器检测与安装
│   ├── sudoers.sh         # sudo 组与 NOPASSWD 管理
│   ├── download.sh        # 下载器选择
│   └── repos.sh           # clone、复制、覆盖与备份
└── tests/
    ├── Dockerfile
    ├── run.sh
    ├── integration.sh
    └── system-integration.sh
```
