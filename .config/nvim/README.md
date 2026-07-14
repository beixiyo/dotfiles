# Neovim 配置

> 基于 Neovim 0.12+ 的 `vim.pack` 插件系统。这个入口页只放安装、插件管理和排障，详细教程见 [GitHub Wiki](https://github.com/beixiyo/dotfiles/wiki)

## 插件演示

<table align="center">
  <tr>
    <td align="center"><a href="https://github.com/beixiyo/vv-dashboard.nvim">vv-dashboard.nvim ↗<br><img src="https://raw.githubusercontent.com/beixiyo/vv-dashboard.nvim/main/docs/assets/vv-dashboard.png" alt="vv-dashboard.nvim demo" width="300"></a></td>
    <td align="center"><a href="https://github.com/beixiyo/vv-explorer.nvim">vv-explorer.nvim ↗<br><img src="https://raw.githubusercontent.com/beixiyo/vv-explorer.nvim/main/docs/assets/vv-explorer.png" alt="vv-explorer.nvim demo" width="300"></a></td>
    <td align="center"><a href="https://github.com/beixiyo/vv-bufferline.nvim">vv-bufferline.nvim ↗<br><img src="https://raw.githubusercontent.com/beixiyo/vv-bufferline.nvim/main/docs/assets/vv-bufferline.png" alt="vv-bufferline.nvim demo" width="300"></a></td>
  </tr>
  <tr>
    <td align="center"><a href="https://github.com/beixiyo/vv-git.nvim">vv-git.nvim ↗<br><img src="https://raw.githubusercontent.com/beixiyo/vv-git.nvim/main/docs/assets/vv-git.png" alt="vv-git.nvim demo" width="300"></a></td>
    <td align="center"><a href="https://github.com/beixiyo/vv-flow.nvim">vv-flow.nvim ↗<br><img src="https://raw.githubusercontent.com/beixiyo/vv-flow.nvim/main/docs/assets/vv-flow.png" alt="vv-flow.nvim demo" width="300"></a></td>
    <td align="center"><a href="https://github.com/beixiyo/vv-i18n.nvim">vv-i18n.nvim ↗<br><img src="https://raw.githubusercontent.com/beixiyo/vv-i18n.nvim/main/docs/assets/vv-i18n.png" alt="vv-i18n.nvim demo" width="300"></a></td>
  </tr>
  <tr>
    <td align="center"><a href="https://github.com/beixiyo/vv-replace.nvim">vv-replace.nvim ↗<br><img src="https://raw.githubusercontent.com/beixiyo/vv-replace.nvim/main/docs/assets/vv-replace.png" alt="vv-replace.nvim demo" width="300"></a></td>
    <td align="center"><a href="https://github.com/beixiyo/vv-hover.nvim">vv-hover.nvim ↗<br><img src="https://raw.githubusercontent.com/beixiyo/vv-hover.nvim/main/docs/assets/vv-hover.png" alt="vv-hover.nvim demo" width="300"></a></td>
    <td align="center"><a href="https://github.com/beixiyo/vv-indent.nvim">vv-indent.nvim ↗<br><img src="https://raw.githubusercontent.com/beixiyo/vv-indent.nvim/main/docs/assets/vv-indent.png" alt="vv-indent.nvim demo" width="300"></a></td>
  </tr>
  <tr>
    <td align="center"><a href="https://github.com/beixiyo/vv-scrollbar.nvim">vv-scrollbar.nvim ↗<br><img src="https://raw.githubusercontent.com/beixiyo/vv-scrollbar.nvim/main/docs/assets/vv-scrollbar.png" alt="vv-scrollbar.nvim demo" width="300"></a></td>
    <td align="center"><a href="https://github.com/beixiyo/vv-statuscol.nvim">vv-statuscol.nvim ↗<br><img src="https://raw.githubusercontent.com/beixiyo/vv-statuscol.nvim/main/docs/assets/vv-statuscol.png" alt="vv-statuscol.nvim demo" width="300"></a></td>
    <td align="center"><a href="https://github.com/beixiyo/vv-task-panel.nvim">vv-task-panel.nvim ↗<br><img src="https://raw.githubusercontent.com/beixiyo/vv-task-panel.nvim/main/docs/assets/vv-task-panel.png" alt="vv-task-panel.nvim demo" width="300"></a></td>
  </tr>
  <tr>
    <td align="center"><a href="https://github.com/beixiyo/vv-log-hl.nvim">vv-log-hl.nvim ↗<br><img src="https://raw.githubusercontent.com/beixiyo/vv-log-hl.nvim/main/docs/assets/vv-log-hl.png" alt="vv-log-hl.nvim demo" width="300"></a></td>
    <td align="center"><a href="https://github.com/beixiyo/vv-mcp.nvim">vv-mcp.nvim ↗<br><img src="https://raw.githubusercontent.com/beixiyo/vsc-lsp-mcp/main/docAssets/demo.webp" alt="vv-mcp.nvim demo" width="300"></a></td>
    <td></td>
  </tr>
</table>

其他暂未提供截图的插件：[vv-utils.nvim](https://github.com/beixiyo/vv-utils.nvim) · [vv-icons.nvim](https://github.com/beixiyo/vv-icons.nvim) · [vv-expand.nvim](https://github.com/beixiyo/vv-expand.nvim) · [vv-markdown.nvim](https://github.com/beixiyo/vv-markdown.nvim)

## 安装

### 前置依赖

- Neovim 0.12+
- [Git](https://github.com/git/git)
- [ripgrep](https://github.com/BurntSushi/ripgrep)
- [fd](https://github.com/sharkdp/fd)
- C 编译器与 [tree-sitter-cli](https://github.com/tree-sitter/tree-sitter/tree/master/crates/cli)
- [Nerd Font](https://www.nerdfonts.com/font-downloads)，推荐 [Maple Mono NF](https://github.com/subframe7536/maple-font/releases)

字体安装和基础命令行工具已经纳入 dotfiles 根目录的[完整安装流程](../../README.zh-CN.md#安装)。`setup-deps.sh` 会根据当前系统的包管理器安装 Git、Neovim、ripgrep、fd 等工具；C 编译器和 `tree-sitter-cli` 请按下方说明安装

**C 编译器 + tree-sitter-cli（TreeSitter 依赖）**
  - [Windows w64devkit](https://github.com/skeeto/w64devkit/releases)
  - Linux Debian `sudo apt install build-essential -y`
  - Arch `paru -S base-devel tree-sitter-cli`

### 部署配置

Neovim 配置包含在 [dotfiles](https://github.com/beixiyo/dotfiles) 中。请按照根目录的[安装流程](../../README.zh-CN.md#安装)完成部署，然后启动 Neovim：

```bash
nvim
```

首次启动时，插件管理器会下载已启用的插件

## 开启插件

本配置基于 Neovim 0.12+ 原生 `vim.pack` API，自建了一套「one-file-per-plugin spec + GUI 管理器」，字段命名与 lazy.nvim 对齐，**不依赖 lazy.nvim / packer**

1. 启动 nvim 进入 Dashboard（首页）
2. 按下 **p** 打开 `:PluginManager`，用 `<CR>` 或 `x` 启用/禁用插件；每次切换都会立即写入配置
3. 用 `q` 或 `<Esc>` 关闭面板，然后重新启动 nvim，引擎会自动 `vim.pack.add` 下载新启用的插件
4. 更新插件：`:PackUpdate [name ...]`（无参数则全量更新；有参支持 tab 补全）
5. 查看加载性能：`:PackStats` 打开浮窗（`s` 按耗时 / `n` 按名称 / `e` 仅 eager / `a` 全部 / `q` 关闭）；脚本场景用 `:PackStatsEcho` 打印到 `:messages`

插件添加/删除的完整流程见 [AGENTS.md](AGENTS.md)

## LSP 安装

输入 `:Mason` 进入 LSP 选择页面，选中后按下 `i` 安装，也可以按下 `Ctrl-f` 先筛选语言

比如 `ts` 可以安装 `tsgo`

---

## 常见错误排查

### `vim.pack API 不存在` / Neovim 版本过低

**现象**：启动时提示 `[nvim-pack] vim.pack API 不存在，请升级 Neovim 到 0.12 或更高版本`

**原因**：本配置依赖 Neovim 0.12+ 提供的原生 `vim.pack` API

**修复**：升级 Neovim 到 0.12+（建议直接用官方 release 或 [bob](https://github.com/MordechaiHadad/bob) 等版本管理器）

### 插件下载失败 / 克隆不完整

**现象**：启动时报某插件模块 `not found`，或 `:checkhealth` 中提示缺文件

**原因**：`git clone` 中断、网络异常，或目标目录残留了空壳

**排查与修复**：

1. 确认 `git` 已安装：

```bash
sudo apt install -y git   # Debian/Ubuntu
```

2. 查看 Neovim 数据目录（受 `XDG_DATA_HOME` / `NVIM_APPNAME` 影响）：

```bash
nvim --headless +'lua print(vim.fn.stdpath("data"))' +q
```

`vim.pack` 将插件克隆到 `<data>/site/pack/core/opt/<plugin>`

3. 删除有问题的插件目录后重启 nvim，引擎会自动重新 `vim.pack.add`：

```bash
rm -rf ~/.local/share/nvim/site/pack/core/opt/<plugin-name>
nvim
```

4. 也可用 `:PackUpdate <plugin-name>` 触发重新拉取

### 代码着色不正确 / TreeSitter parser 编译失败

**现象**：代码没有语法高亮，或 `:checkhealth nvim-treesitter` 显示 `tree-sitter-cli not found`

**原因**：新版 `nvim-treesitter` 需要 `tree-sitter-cli` 0.26.1 或更高版本来编译 parser。缺少或版本过低时，parser 无法生成，着色会回退到基础正则匹配

**排查与修复**：

1. 检查 `tree-sitter-cli` 是否安装：

```bash
tree-sitter --version
```

2. 未安装则根据系统安装：

```bash
# Arch
paru -S tree-sitter-cli

# Debian/Ubuntu（系统仓库版本过低时使用 Cargo）
cargo install tree-sitter-cli
```

3. 安装后重新编译 parser：

```vim
:TSUpdate
```

4. 验证：执行 `:checkhealth nvim-treesitter`，确认 CLI、编译器和 parser 检查通过

---

## 文档入口

- [GitHub Wiki](https://github.com/beixiyo/dotfiles/wiki) - 使用教程、快捷键、配置说明与 Neovim API
- [AGENTS.md](AGENTS.md) - 插件添加/删除指南，基于 `vim.pack` 和单文件 spec
- [vendors/](vendors/) - 本地插件源码
