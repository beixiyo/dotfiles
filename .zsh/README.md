# Zsh 工作流

这套配置把常用开发操作压缩成短命令，并用 fzf 提供可预览、可多选、可直接执行操作的终端面板

复杂的数据处理和交互界面由 Bun + TypeScript 完成，Zsh 只负责 `cd`、`export` 等必须影响当前 Shell 的操作

> 安装、平台依赖与新机器部署统一见 [one-click-config/README.md](../one-click-config/README.md)

## 高频命令

| 命令 | 作用 |
|---|---|
| `d` | 自动识别项目并启动开发服务 |
| `b` | 自动识别项目并执行构建 |
| `i [pkg...]` | 安装项目依赖，或添加指定包 |
| `t` | 自动识别项目并运行测试 |
| `ff [path]` | 搜索文件和目录，显示预览并复制路径 |
| `fs [path]` | 使用 ripgrep 实时搜索项目内容并跳到准确行号 |
| `fx [path]` | 在同一个面板中切换文件搜索与全文搜索 |
| `fp [port]` | 按应用聚合进程，查看端口和内存并批量结束 |
| `dd` | 在统一面板中管理 Docker 容器和镜像 |
| `grepo [path]` | 搜索 Git 仓库并进入所选目录 |
| `gdiff [path]` | 预览、暂存和取消暂存 Git diff |
| `glog` | 搜索并预览 Git 提交历史 |
| `nvd [path]` | 从 tmux、Kitty 或普通终端启动 Neovide，并保留当前工作目录 |

## 项目命令：`d / b / i / t`

这些命令根据项目文件自动选择执行方式：

| 项目 | 识别文件 | 支持的操作 |
|---|---|---|
| Node.js | `package.json` | 根据 lock 文件选择 pnpm、Bun、Yarn 或 npm |
| Go | `go.mod` | `go run / build / get / test` |
| Rust | `Cargo.toml` | `cargo run / build / add / test` |
| Python | `pyproject.toml` 或 `uv.lock` | 使用 uv 运行、构建、同步依赖和测试 |
| Maven | `pom.xml` | Spring Boot 开发、构建、安装和测试 |
| Flutter | `pubspec.yaml` | 运行、构建、获取依赖和测试 |

```bash
d              # pnpm run dev / bun run dev / yarn run dev / npm run dev
b              # 执行项目 build
i              # 安装全部依赖
i vite zod    # 添加指定依赖
t              # 执行项目 test
```

Node.js 包管理器优先读取当前目录的 lock 文件；没有 lock 文件时按 pnpm、Bun、Yarn、npm 的可用顺序选择

Go 和 Rust 使用语言官方工具链的默认命令。Python 使用 uv：`i` 同步依赖、`i package` 添加依赖、`b` 构建发行包、`t` 运行 pytest。Python 没有统一的开发启动命令，因此 `d` 会优先运行 `main.py` 或 `app.py`；其他项目使用 `d <command> [args...]` 明确指定入口

## 文件与内容搜索

### `ff`：文件和目录

```bash
ff             # 当前目录下搜索文件和目录
ff src         # 从 src 开始搜索
ff -f          # 只显示文件
ff -d          # 只显示目录
ff -I          # 包含被 Git 忽略的内容
```

面板操作：

| 快捷键 | 操作 |
|---|---|
| `Enter` | 返回相对路径和绝对路径 |
| `Ctrl+O` | 用 VS Code 打开 |
| `⌥O` | 用 Neovim 打开 |
| `⌥C` | 复制绝对路径 |
| `⌥F / ⌥D / ⌥A` | 切换文件、目录、全部 |
| `Ctrl+N / P` | 向下、向上移动 |
| `Ctrl+E / Y` | 滚动预览 |

`Ctrl` 和 `Alt` 前缀可通过 `fzfCmdBind`、`fzfOptionBind` 环境变量调整

### `fs`：实时全文搜索

`fs` 使用 ripgrep 搜索隐藏文件，遵守 Git ignore，并在右侧显示匹配位置的上下文

```bash
fs             # 搜索当前目录
fs packages    # 搜索 packages
fs -I          # 包含被 Git 忽略的内容
```

`Ctrl+O` 用 VS Code 打开准确行号，`⌥O` 用 Neovim 打开，`⌥C` 复制路径

### `fx`：统一搜索面板

`fx` 把 `ff` 和 `fs` 合并在同一个界面：

- `Tab` / `Shift+Tab` 在 **Files** 和 **Grep** 之间切换
- 底部操作栏显示 `Select ↵ │ Code ^O │ nvim ⌥O │ Copy ⌥C`
- 可以直接点击底部操作

## 进程管理：`fp`

不传参数时，`fp` 按应用名称聚合相关进程，显示总内存、监听端口和启动命令

```bash
fp        # 浏览全部进程
fp 9977   # 只查看监听 9977 端口的进程
```

| 快捷键 | 操作 |
|---|---|
| `Ctrl+E` | 展开或折叠同一应用的子进程 |
| `Tab` | 多选 |
| `⌥C` | 复制进程信息 |
| `Enter` | 结束选中的进程或进程组 |

### `ports`：监听端口

`ports` 只列出正在监听的 TCP 端口，适合快速确认端口占用并结束对应进程：

```bash
ports             # 查看当前用户可见的监听端口
ports 9977        # 只查看 9977 端口
ports --all       # 使用 sudo 查看所有监听端口
ports 9977 --all  # 使用 sudo 查看指定端口
```

| 快捷键 | 操作 |
|---|---|
| `Tab` | 选中当前项并自动移动到下一项，可连续多选 |
| `Enter` | 结束选中的进程；Bun 可用时会先显示进程并确认 |

## Docker 面板：`dd`

`dd` 会先确认 Docker daemon 可用；macOS 可尝试启动 Docker Desktop，Linux 可使用当前用户权限或 sudo

面板同时显示容器和镜像，支持多选：

| 快捷键 | 操作 |
|---|---|
| `l` | 查看容器日志 |
| `e` | 进入容器 |
| `c` | 复制容器 ID |
| `s` | 停止容器 |
| `r` | 启动容器 |
| `R` | 重启容器 |
| `d` | 停止并删除容器 |
| `i` | 删除镜像 |
| `Ctrl+R` | 刷新列表 |

其它 Docker 命令：

| 命令 | 作用 |
|---|---|
| `dex` | 选择运行中的容器并进入 bash 或 sh |
| `dlogs` | 选择容器并持续查看日志 |
| `dlog <name>` | 查看指定容器从本次启动开始的日志 |
| `dcp` | 选择容器并输出或复制 ID |
| `dinfo <repo> <tag>` | 查看 Docker Hub 镜像的 digest 和大小 |

## Git 工作流

| 命令 | 作用 |
|---|---|
| `grepo [path]` | 递归发现 Git 仓库，预览状态并进入所选仓库 |
| `gdiff [path]` | 查看 staged、unstaged 和 untracked 变更，并执行 stage / unstage |
| `glog` | 搜索提交、预览 diff 并复制 hash |
| `gwt-sync [path]` | 交互选择同步目标；也可用 `--json` 直接传参供脚本或 AI 调用 |
| `gitpt [version] [-r remote]` | 发布 SemVer tag；无参数时确认下一个 patch 或手动输入 tag，默认推送到 `origin` |

各个 fzf 面板直接显示紧凑的快捷键提示，例如 `Open ↵`、`Stage ^S`、`nvim ⌥O`；Alt/Option 在所有平台统一显示为 `⌥`

### `gwt-sync`：安全更新 worktree

`gwt-sync` 默认读取当前 Git 仓库，也可以接收仓库中的任意目录。它依次选择
worktree、remote、目标分支和同步策略，获取最新远程引用后才计算 ahead/behind：

```bash
gwt-sync
gwt-sync ~/Documents/code/frontend/flowtica-internal-flow
```

- 仅落后时使用 `merge --ff-only`；已经分叉时明确选择 rebase 或 merge
- merge/fast-forward 使用 `merge-tree` 预检；rebase 在临时 detached worktree 中实际重放
- 预检包含 staged、unstaged 和未跟踪文件，不只比较 `HEAD`
- 目标新增路径以及 rebase 中间提交会写入的路径，都会检查本地 ignored 同名及父子冲突，避免 Git 静默覆盖
- dirty submodule 或嵌套仓库会直接阻止更新，必须先在各自仓库处理
- 预检无冲突时最终确认默认执行；dirty worktree 会自动临时 stash，并用 `--index` 恢复暂存边界
- 普通 Git 冲突会询问是否仍然尝试更新；ignored 覆盖、dirty submodule/嵌套仓库等安全风险不可绕过
- 执行前重新校验 index/worktree tree；更新失败时按阶段保留 stash 和备份引用

无需 TTY 的机器模式直接使用 PATH 中的 `gwt-sync`，`--target` 同时包含 remote
和远程分支，例如 `origin/master`。`--json` 隐含非交互，默认 fetch 后只预检；
它会更新远程跟踪引用，但不会移动真实分支或改写 index/worktree：

```bash
gwt-sync \
  --worktree /abs/path/to/worktree \
  --target origin/master \
  --strategy rebase \
  --json
```

只有显式传入 `--apply` 才会执行更新。已知存在普通 Git 冲突时，即使传了
`--apply` 也只返回冲突；必须再加 `--allow-conflicts` 才会进入需要人工恢复的
真实冲突状态。仅落后目标时始终采用 `ff-only`，此时 JSON 中会同时保留
`strategy.requested` 并将 `strategy.effective` 标为 `ff-only`

stdout 始终只包含一个 JSON 对象，其中包括 worktree 路径和当前分支、目标
remote/分支/OID、ahead/behind、dirty 文件、冲突文件和原始冲突 diff、执行结果
以及失败后的恢复命令。稳定退出码如下：

| 退出码 | 含义 |
|---|---|
| `0` | 已可安全更新、无需更新或更新成功 |
| `1` | 参数、路径、fetch 或其他运行错误 |
| `2` | 发现普通 Git 冲突，未执行更新 |
| `3` | 安全边界阻止更新，或分叉分支缺少有效策略 |
| `4` | 已尝试更新但失败，JSON 中包含恢复信息 |

## 其它命令

| 分类 | 命令 | 作用 |
|---|---|---|
| 文件 | `mkcd <dir>` | 创建目录并进入 |
| 文件 | `lt [depth] [path]` | 使用 lsd 输出树状目录 |
| 文件 | `rmr <root> <pattern...>` | 按模式递归查找并删除 |
| 文件 | `rme <keep...>` | 删除指定名称以外的内容 |
| 文件 | `open [path]` | 使用系统文件管理器打开 |
| 网络 | `myip` | 查看公网 IP 和地理信息 |
| 网络 | `ports [port] [--all]` | 查看监听端口并选择进程结束 |
| 网络 | `adblockHosts` | 依次尝试多个镜像拉取广告屏蔽 hosts，合并进 `/etc/hosts` 的托管区块（会警告 + 自动备份，标记外内容不动） |
| 网络 | `refreshGithubHosts` | 拉取 GitHub520 hosts，替换其专属托管区块（会警告 + 自动备份，标记外内容不动） |
| SSH | `cssh [query]` | 搜索 SSH 主机并连接 |
| SSH | `cscp [path]` | 交互式 SCP 上传和下载 |
| 代理 | `setProxy [port]` / `unsetProxy` | 切换 Shell 与 Git 代理 |
| 包管理 | `ins <pkg...>` / `uns <pkg...>` | 跨发行版安装和卸载软件 |
| 包管理 | `update [pkg...]` | 更新指定软件或整个系统 |
| 包管理 | `pkgs` | 交互式查看已安装软件包 |
| 下载 | `download <url> [path]` | 按 aria2c、wget、curl 顺序选择下载器 |
| 系统 | `cb` | 跨平台复制或读取剪贴板 |
| 系统 | `sysinfo` | 查看 OS、CPU、内存、磁盘与运行时间 |
| Mihomo | `mihomo-set [node]` | 测速并切换代理节点 |

## 架构

```text
~/.zsh/
├── functions/*.zsh          # 改变当前 Shell 状态的薄封装
├── functions/bun/src/*.ts   # fzf 界面、数据处理和复杂逻辑
├── functions/_preview/      # fzf 预览脚本
├── functions/_actions/      # fzf 操作回调
├── functions/pkg/           # 跨平台包管理
├── plugins/                 # Zsh 插件
├── aliases.zsh              # 条件别名
├── env.zsh                  # 环境变量与 PATH
└── tools.zsh                # Starship、Mise、Zoxide、Fzf 等外部工具集成
```

详细开发约定见 [AGENTS.md](AGENTS.md)

## 定制

- 别名：编辑 `~/.zsh/aliases.zsh`
- 环境变量和 PATH：编辑 `~/.zsh/env.zsh`
- 简单 Shell 函数：放在 `~/.zsh/functions/*.zsh`
- fzf 和复杂逻辑：放在 `~/.zsh/functions/bun/src/*.ts`
- 通用工具：优先复用 `functions/utils/` 和 `functions/bun/src/utils.ts`
