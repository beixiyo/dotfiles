# Vim 配色导出

本目录的 `colors/*.vim` 是生成产物，颜色来源是 `lua/tokyonight/colors/` 调色板与 `lua/tokyonight/groups/` 高亮组，不直接编辑生成文件

## 生成与加载

在本 fork 根目录运行（使用隔离配置，避免加载用户插件）：

```sh
nvim --headless -u NONE --cmd 'set runtimepath^=.' \
  +"lua require('tokyonight.extra')" +qa
```

当前生成 `moon`、`pretty_moon`、`pretty_cat` 三种配色。在 Vim 中加载：

```vim
set termguicolors
set rtp+=~/.config/nvim/vendors/tokyonight.nvim/extras/vim
colorscheme tokyonight-pretty_cat
```

加载生成文件不需要运行 Neovim；仅生成时需要 Neovim

## 单文件 Vim UI 的颜色边界

- `lua/tokyonight/extra/vim.lua` 为经典 Vim 补齐 `SL*` 状态栏组与 `MiniExplorerIcon*` 图标组，使用当前调色板或链接到已有主题组，不影响 Neovim 运行时高亮
- `~/.vimrc` 的 `SetupUIHighlights` 只用 `highlight default link` 提供缺省语义链接，不覆盖主题的状态栏、搜索或选区颜色
- 模式块复用 `MiniStatuslineMode*`，部分图标复用 `MiniIcons*`；这些是导出的颜色组，不需要安装 Mini 插件
- 主题文件缺失或非真彩终端时，`.vimrc` 使用内置 `habamax` 配色与缺省链接，不再维护一份 pretty_cat 色值或 256 色近似表
- 导出器显式覆盖 `term` / `cterm` / `gui` 样式，清空 `ctermfg` / `ctermbg` 与未指定的 RGB 字段；`hi clear` 会恢复内置默认值，单写 `guibg=NONE` 仍可能让拼写高亮露出内置蓝色 / 粉色背景
- 修改调色板或 Vim 专用 UI 组后重新生成；在 Vim 中执行 `:colorscheme tokyonight-pretty_cat` 加载新产物
