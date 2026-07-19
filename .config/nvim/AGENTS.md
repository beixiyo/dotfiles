# AGENTS.md — 插件添加指南

本配置基于 Neovim 0.12+ 原生 `vim.pack` API，自实现了一套「one-file-per-plugin spec + 懒加载 + GUI 管理」系统（字段命名与 lazy.nvim 对齐）。所有插件以**单文件 spec** 方式声明：元数据、opts、config、懒加载触发器、build 全写在一个文件里。字段名刻意向 lazy.nvim 靠拢，方便直接抄 LazyVim 示例

## 目录结构

```
lua/
├── pack/                              引擎层（不要改，除非修 bug）
│   ├── init.lua                       扫描 spec → 过滤 → vim.pack.add → 按 priority 降序分发
│   ├── spec.lua                       名称/路径解析 + url 短名展开 + main 自动推断（normname 扫 lua/）
│   ├── scan.lua                       扫 plugins/specs/ 下所有 spec 文件
│   ├── loader.lua                     单 spec 消费：rtp/dependencies/packadd/main/opts/config
│   ├── lazy.lua                       声明式懒加载：event/ft/cmd/keys，keys 用 expr=true + feedkeys 模式
│   ├── sync.lua                       清理被禁用插件的磁盘目录
│   ├── build.lua                      spec.build 执行与更新监听
│   ├── stats.lua                      _G.PackStats 计数；monkey-patch loader.load
│   ├── commands.lua                   :PackUpdate [name ...] / :PackStats
│   └── smoke.lua                      :lua require('pack.smoke').run() 冒烟测试
│
├── plugins/
│   ├── specs/                         ★ 一插件一文件
│   │   ├── code/                      code category（lsp / 补全 / treesitter 等）
│   │   ├── tools/                     tools category（跳转 / 搜索 / 会话等）
│   │   └── ui/                        ui category（状态栏 / 主题 / 树等）
│   └── manager/
│       ├── init.lua                   :PluginManager 浮窗 UI
│       ├── commands.lua               :PluginManager + <leader>fp
│       └── user-picks.lua             禁用集合（[id] = false，默认全启用）
│
└── vendors/                           本地 / 离线 / fork 的插件源码
```

## 添加一个新插件：新建一个 spec 文件即可

### 1. 文件放在 `lua/plugins/specs/<category>/<id>.lua`

- `<category>` = `code` | `tools` | `ui`，决定 `:PluginManager` 归属
- `<id>` = 文件名（不带 `.lua`），作为唯一 key（user-picks / stats 都用它）
- 或者用目录形态 `<category>/<id>/init.lua`（需要辅助模块时用）

scan 会自动从路径推出 `id` 和 `category`，spec 内无需显式写

### 2. spec 文件返回一张表

```lua
-- lua/plugins/specs/code/my-plugin.lua
-- 一句话说明 + 官方文档链接
return {
  desc         = '一句话描述（显示在 :PluginManager）',
  url          = 'author/my-plugin',                     -- 短名默认 GitHub；也可写完整 URL
  -- main      = 'my_plugin',                            -- 可省略，自动按 normname 扫 dir/lua/ 推断
  dependencies = { 'nvim-lua/plenary.nvim' },

  -- 懒加载触发器（任一命中即注册声明式懒加载）
  cmd    = { 'MyPluginOpen' },
  keys   = {
    { '<leader>mp', function() require('my_plugin').toggle() end, desc = 'My Plugin' },
  },

  -- opts：table 或 function(plugin) -> table
  opts = {
    foo = true,
  },

  -- config 可选；不写时走默认 require(main).setup(opts)
  config = function(_, opts)
    require('my_plugin').setup(opts)
    vim.api.nvim_set_hl(0, 'MyPluginLabel', { bold = true })
  end,

  build  = ':TSUpdate',      -- 可选，安装/更新后执行
  -- version = '*',          -- 可选，等价于 vim.pack.add 的 version；branch/tag/commit 也会转到它
}
```

### 3. 字段说明

| 字段 | 必填 | 说明 |
|------|------|------|
| `desc` | ✓ | GUI 中文描述 |
| `url` | △ | 远程仓库。与 `dir` 二选一。支持 `'owner/repo'` 短名（默认 GitHub）、完整 URL、或 `{ src = '...', version = '...' }` 表 |
| `dir` | △ | 本地路径（`vendors/xxx`），用于 vendor 或 fork |
| `main` | ✗ | 主模块名。**可省略**：自动按 lazy.nvim 的 `normname` 规则扫 `dir/lua/` 推断（`nvim-lspconfig → lspconfig`、`tokyonight.nvim → tokyonight`）。显式写 `main = 'xxx'` 覆盖；`main = false` 明确跳过 require（VimL 插件、FFI 库） |
| `id` | ✗ | 默认取文件名；显式覆盖只在极少数场景需要 |
| `category` | ✗ | 默认取父目录名 |
| `dependencies` | ✗ | 依赖 URL 列表，一并 clone 并在主插件前 `packadd`；也支持短名 `'owner/repo'` |
| `priority` | ✗ | 加载顺序，**降序**（大的先）。colorscheme / 共享库（vv-utils、vv-icons）写 100+；默认 0 |
| `init` | ✗ | `function(plugin)`，`packadd` 之前执行，用来设 `vim.g.xxx` 等预配置 |
| `opts` | ✗ | table 或 `function(plugin) -> table` |
| `config` | ✗ | `function(plugin, opts)`；不写时走默认 `require(main).setup(opts)`。需要 plugin 对象时在函数内 `require(...)` |
| `build` | ✗ | 安装/更新后执行：Ex 命令字符串（`':TSUpdate'`）、shell 命令、或 `":lua require('xxx').build()"` |
| `version` / `branch` / `tag` / `commit` | ✗ | git 引用锁定。按优先级 `commit > tag > version > branch` 转发给 `vim.pack.add` 的 `version` 字段 |
| `cond` | ✗ | 自定义加载条件：`function` 返回 `false`、或值 `false`，都会跳过 |
| `loadInVSCode` | ✗ | 默认 `false`。VSCode-Neovim 环境下只有 `true` 的 spec 被加载 |
| `name` | ✗ | 手动指定 `packadd` 名称，通常不需要 |

**懒加载字段**（写了任一就走声明式懒加载路径）：

| 字段 | 形式 | 说明 |
|------|------|------|
| `event` | `{ 'InsertEnter', ... }` 或单个字符串 | 首次事件触发时加载 |
| `ft` | `{ 'lua', 'markdown' }` | FileType 匹配时加载 |
| `cmd` | `{ 'Trouble' }` | 首次执行该命令时加载，并重放命令 |
| `keys` | `{ { lhs, rhs, mode=..., desc=..., ft=..., expr=..., nowait=..., silent=..., remap=..., noremap=... }, ... }` | 装 `expr=true` 占位 keymap，首次触发 → del 占位 → 加载 → 装真 rhs → `feedkeys <Ignore>lhs`。走完整 keymap 解析，operator-pending / count / motion 行为正确 |
| `lazy = 'manual'` | — | **逃生舱**：引擎仅扫/注册，`config(plugin, { load = fn })` 在启动期立即执行，由 spec 自己决定加载时机（参考 `treesitter.lua` 在 FileType 回调里异步装 parser） |

`keys` 要点：
- rhs 可为 function、`'<cmd>Foo<cr>'` 字符串，或省略（加载后让插件自绑 keymap 接管）
- `mode` 默认 `{ 'n', 'x', 'o' }`；可写单字符串 `'n'` 或数组
- `ft = 'lua'`：buffer-local keymap，只在对应 filetype 中生效
- rhs 为 `'<Nop>'` / `''`：直接装真 keymap 不触发加载

### UI 配色约定

- UI spec / vendor 插件需要跟随当前 tokyonight style 时，优先从 `tools.palette` 取项目统一色板，不要在 spec 里散落硬编码色值：

  ```lua
  local p = require('tools.palette').get()
  ```

- 如果只需要判断当前 style，使用：

  ```lua
  local style = require('tools.palette').style('night')
  ```

- 现有参考：[bufferline.lua](lua/plugins/specs/ui/bufferline.lua)、[lualine/theme.lua](lua/plugins/specs/ui/lualine/theme.lua)、[vv-scrollbar.lua](lua/plugins/specs/ui/vv-scrollbar.lua)

**`cond` vs `loadInVSCode`**

- `loadInVSCode` 是 VSCode 场景的**白名单开关**：默认全部插件在 VSCode 下都不加载
- `cond` 是任意环境的运行时判断：

  ```lua
  -- neoscroll 在 Neovide 下不启用（Neovide 已有原生平滑滚动）
  cond = function() return not vim.g.neovide end,
  ```

### 4. 重启 Neovim

- 启动时 [pack/init.lua](lua/pack/init.lua) 会自动 `vim.pack.add` 下载新插件
- `:PluginManager`（`<leader>fp`）打开 GUI，可切换启用/禁用（写回 `user-picks.lua`）
- `:PackUpdate [name ...]` 更新插件（无参=全部；有参支持 tab 补全，按 pack 管理名）
- `:PackStats` 打开性能分析浮窗（`s`/`n` 切换排序、`e`/`a` 切换过滤、`q` 关闭）
- `:PackStatsEcho` 在 `:messages` 打印文本版统计（headless / 脚本用）

---

## 本地 / vendor 插件

源码放在 [vendors/](vendors/)，有两种方式让 spec 走本地源码：

### 方式一：spec 显式写 `dir`（纯 vendor / fork）

```lua
-- lua/plugins/specs/ui/hover.lua
return {
  desc = '鼠标悬停自动 Hover',
  dir  = vim.fn.stdpath('config') .. '/vendors/vv-hover.nvim',
  -- main = 'hover',  -- 可省略，自动从 dir/lua/ 推断
}
```

### 方式二：`pack/dev.lua` 自动重定向（开发调试远程插件的本地 fork）

[pack/dev.lua](lua/pack/dev.lua) 实现了类似 lazy.nvim `dev = {...}` 的机制：**spec 照常写 `url`，启动时自动检测是否有本地副本，有则重定向到本地目录**

**工作原理**：

1. `M.config.patterns`（默认 `{ 'beixiyo' }`）定义 URL 子串匹配规则
2. 启动时对每个 spec 调用 `M.redirect(spec)`：
   - spec.url 命中 patterns 且 `vendors/<repo-name>/` 目录存在 → `spec.url` 转为 `spec.dir`，走本地源码
   - 本地目录不存在 → 回退远程 clone（`fallback = true`）
3. 原始 url 备份到 `spec._dev_origin_url`，可通过 `:PackDev` 查看

**三种控制粒度**：

| 控制方式 | 行为 |
|---------|------|
| url 命中 `patterns` | 自动走本地（本地不存在则回退远程） |
| spec 显式 `dev = true` | 强制走本地（本地不存在时 warn，按 `fallback` 决定跳过还是回退） |
| spec 显式 `dev = false` | 永远走远程，即使命中 patterns |

**配置**（在 [pack/dev.lua](lua/pack/dev.lua) 顶部）：

```lua
M.config = {
  path     = vim.fn.stdpath('config') .. '/vendors',  -- 本地仓库父目录
  patterns = { 'beixiyo' },                           -- URL 子串匹配列表
  fallback = true,                                    -- 本地不存在时回退远程
}
```

**调试命令**：

- `:PackDev` — 列出当前所有走 dev 模式的插件（显示 id、本地 dir、原始 url）
- `:PackDev <name>` — 查看某个插件的判定细节（是否命中、本地路径是否存在等）

**典型开发流**：自己的 GitHub 插件（owner 含 `beixiyo`）只需把源码 clone 到 `vendors/` 下，spec 保持写 `url = 'beixiyo/xxx'`，dev 机制自动切到本地；push 到远程后删掉本地目录即恢复远程 clone

---

## 开发 vendor 插件：**先查 vv-utils，再动手**

在写任何 vendor 插件（`vendors/vv-*.nvim/`）之前，**必须**先过一遍 [vv-utils.nvim](https://github.com/beixiyo/vv-utils.nvim)，已有的能力一律复用，不要重复造轮子。"自己手写一版凑合能用"是**反模式** —— 视觉不统一、行为不一致、bug 各搞各的，改一次得改 N 遍

### 常见复用触发点对照表

写到如下代码时，**先停下**查下表：

| 你想做 | 别写 | 直接用 |
|------|------|------|
| **帮助/键位浮窗** | 自己 `nvim_open_win` + 手拼 lines + 硬编码颜色 | `vv-utils.help_panel.open({ source_buf, desc_prefix = 'vv-xxx: ', actions, categories, title, title_icon })`。keymap 时统一 `desc = 'vv-xxx: <action>'`，浮窗反读 buffer keymap 自动渲染（含图标、分类、圆角、q/Esc 关闭）。参考 [vv-explorer help.lua](https://github.com/beixiyo/vv-explorer.nvim/blob/main/lua/vv-explorer/help.lua) / [vv-git help.lua](https://github.com/beixiyo/vv-git.nvim/blob/main/lua/vv-git/help.lua) |
| **git 状态索引** | 自己跑 `git status` 并解析 | `vv-utils.git.index(root, cb, opts?)` → `{status_map, is_ignored, toplevel}`；`opts.untracked = 'all'` 展开未跟踪目录到文件粒度 |
| **git 状态调色板 / 符号** | 每个 vendor 再写一份 VSCode 色 + XY→hl 映射表 | `vv-utils.git.register_hl()` 注册 `VVGitAdded/Modified/Deleted/Renamed/Untracked/Conflict/Ignored`（VSCode Dark+，`default=true` + `ColorScheme` 重挂）；`vv-utils.git.symbol_for(xy)` 返回 `{glyph, hl='VVGit*'}` |
| **高亮组批量注册** | 零散 `nvim_set_hl` + `ColorScheme` 自动 reload 逻辑 | `vv-utils.hl.register(augroup, specs, opts?)`，自动补 `default=true` + `ColorScheme` 重挂 |
| **UI buffer 窗口样式** | 手动关 number/signcolumn/cursorline，BufWipeout 时忘记还原 | `vv-utils.ui_window.hide_chrome(win)` + 自动 restore |
| **替换主窗后残留 [No Name]** | `nvim_buf_delete` 前自己写一堆条件判定 | `vv-utils.bufdelete.wipe_if_throwaway(prev_buf)`（详见下一节） |
| **文件系统操作** | `vim.fn.mkdir` / `os.rename` 手拼 | `vv-utils.fs.*`（`mkdir_p` / `rename` 带 EXDEV 降级 / `copy` 递归 / `unique_dest`） |
| **多文件内容事务 / 单层撤回** | 各插件保存 old/new 后自行校验和回滚 | `vv-utils.fs.new_transaction()`，实例隔离，统一处理快照预检、补偿回滚和 Undo |
| **输入框历史** | 各插件自己维护 Up / Down 游标和 JSON | `vv-utils.history.new({ name, max_entries, persist })`，按字段隔离并可选持久化 |
| **VS Code 风格搜索 glob** | 各插件自己补 `**/`、猜文件或目录 | `vv-utils.glob.split/compile_rg/compile_rg_list`，统一处理 `./` 根锚定、任意深度、brace、排除和路径本体/后代展开 |
| **找项目根** | 手写 `.git` 向上搜 | `vv-utils.path.get_root()` |
| **聚合 LSP 诊断** | 自己 `vim.diagnostic.get` 遍历 | `vv-utils.diagnostics.collect_by_path()` |
| **跨平台打开外部文件** | 根据 OS 写三份命令 | `vv-utils.sys.open_default(path)` |
| **面板防鼠标拖拽 / 多击进 visual** | 只在 buffer 上 Nop（漏 `<3-/4-LeftMouse>`、且跨窗口拦不住） | nop 补全 `<3-/4-LeftMouse>` + `vv-utils.mouse.block_visual_drag(buf)` 兜底（见「鼠标操作规范」） |

### 当前子模块全表

详见 [vv-utils.nvim README](https://github.com/beixiyo/vv-utils.nvim#readme)

| 模块 | 用途 |
|---|---|
| `vv-utils.path` | `norm` / `get_root`（找 `.git`、`package.json`）/ `get_cwd` |
| `vv-utils.glob` | VS Code 风格搜索 glob：顶层逗号拆分、`./` 根锚定、任意深度与 ripgrep pattern 展开 |
| `vv-utils.fs` | fs 原语，以及 `new_transaction()` 提供的多文件完整内容快照、校验、补偿回滚与单层撤回 |
| `vv-utils.git` | 异步 `git status --porcelain --ignored`：`index(root, cb, opts?)` + `is_ignored(path)` + `symbol_for(xy)` + `register_hl(augroup?)` 注册共享 `VVGit*` 调色板；`opts.untracked = 'normal'\|'all'` |
| `vv-utils.diagnostics` | `collect_by_path()` 聚合所有 loaded buffer 的 LSP 诊断 + `symbol_for(counts)` |
| `vv-utils.history` | `new(opts)` 创建隔离实例；`record` / `record_many` / `previous` / `next`，支持草稿恢复和 0600 原子持久化 |
| `vv-utils.sys` | `open_default(path)` 跨平台 `open` / `start` / `xdg-open` |
| `vv-utils.mouse` | `block_visual_drag(buf)` 给 nofile 面板挂 ModeChanged 守卫，禁止鼠标拖拽 / 多击（含跨窗口拖入）进 visual |
| `vv-utils.ui_window` | UI buffer 窗口 chrome 管理（signcolumn / cursorline / restore） |
| `vv-utils.hl` | `register(augroup, specs, opts?)` 批量注册高亮，自动 `ColorScheme` 重挂 |
| `vv-utils.help_panel` | `open(opts)` 通用 keymap 帮助浮窗（反读 buffer keymap 按 desc 前缀分组渲染） |
| `vv-utils.bufdelete` | `wipe_if_throwaway(buf)` 严格判定清理 startup/显式 [No Name] |
| `vv-utils.yaml` | 轻量 YAML 解析（workspaces 用） |
| `vv-utils.editor` | 编辑器相关小工具 |

**引用方式**：`require('vv-utils.git')`、`require('vv-utils.fs')`…；或 `require('vv-utils').git` 走 facade

### 什么时候抽到 vv-utils（新能力入库标准）

- ✅ 真通用：逻辑不依赖任何具体 vendor 的 state / filetype / buffer 生命周期
- ✅ 已有或即将有二次 caller（dashboard / bufferline / statusline / 其它 vendor）
- ❌ 强耦合某个 vendor 的 state 结构（比如 vv-explorer 的 `state.filter` / `state.selection`）
- ❌ "万一以后有人用" 式的预留 —— 等真出现第二个 caller 再抽

抽的模式：**纯数据 / 纯函数放 vv-utils**；订阅 autocmd、debounce timer、调用 `render` 这类**副作用**留在各 vendor 的薄适配层。参考 [vv-explorer git.lua](https://github.com/beixiyo/vv-explorer.nvim/blob/main/lua/vv-explorer/git.lua) 对 `vv-utils.git` 的使用

### vendor 插件配置规范

所有 `vendors/vv-*.nvim` 插件必须遵循以下统一约定：

#### 类型注释

- **@class 命名**：`VVXxxConfig`（如 `VVGitConfig`、`VVExplorerConfig`）。子类型同理：`VVXxxTimingConfig`、`VVXxxKeymaps` 等
- **@field 必须带 @default**：每个 `@field` 行末尾标注 `@default <value>`，让用户在 hover 文档中直接看到默认值
- 导出的 `type` / `interface` 提供 JSDoc（含 `@default`），内部类型可省略

```lua
---@class VVXxxConfig
---@field width integer  面板宽度 @default 40
---@field enabled boolean @default true
```

#### config 封装

- config 用 **`local config`**，不挂 `M.config`。对外暴露只读访问器：

```lua
local config = defaults

function M.setup(opts)
  config = vim.tbl_deep_extend('force', defaults, opts or {})
end

function M.get_config()
  return vim.deepcopy(config)
end
```

#### user command

- **命名**：`VV<PluginName><Action>`（如 `VVGitCompare`、`VVExplorerToggle`、`VVIndentEnable`）
- **覆盖**：所有有意义的操作都注册 user command，方便 spec `keys` 用 `<cmd>VVXxx<cr>` 调用
- **最低要求**：有 setup() 的插件至少注册 `Enable` / `Disable` / `Toggle`（纯数据模块如 vv-icons 除外）
- 命令在 `M.setup()` 内注册

#### 公开 API

- 只暴露生命周期函数：`setup` / `open` / `close` / `toggle` / `enable` / `disable` / `refresh` / `get_config`
- 内部函数用 `_` 前缀：`M._compare_pick()`
- `local` 函数不挂 `M`

#### keymap 分层

| 层次 | 位置 | 规则 |
|------|------|------|
| **① 全局快捷键** | spec `keys[]` | setup() **不**注册全局键，用 spec `keys` + `<cmd>VVXxx<cr>` |
| **① 例外** | setup() | `keymap_toggle_panel` 类「单一生命周期」可保留为 config 项（可设 `false` 关闭） |
| **② 面板内按键** | setup() 内 buffer-local | 硬编码或通过 `config.keymaps` / `config.mappings` 表暴露覆盖 |
| **禁止** | — | 不为业务操作（compare / search / commit 等）加 `keymap_xxx` config 项 |

#### spec 文件同步

- `cmd` 数组与插件实际注册的 user command **一一对应**（漏了会导致 lazy-load 失败）
- `keys` 负责所有全局快捷键绑定，不依赖 setup() 内部注册
- `opts` 只传真正需要定制的字段，其余走默认

### 新增 vendor 插件的 checklist

动手写新 vendor 前确认：

- [ ] 读过 [vv-utils.nvim README](https://github.com/beixiyo/vv-utils.nvim#readme) 当前模块列表
- [ ] 上表"常见复用触发点"每一项都不是你要做的事；如果是，直接用现成 API
- [ ] 需要的能力 vv-utils 没有，但**至少会被两个 vendor 用到** → 加入 vv-utils；只一个用就留在自己的 vendor 里
- [ ] 遵循上方「vendor 插件配置规范」：@class 命名、@default、local config、user command、keymap 分层
- [ ] keymap 统一加 `desc = 'vv-<vendor>: <action>'` 前缀（为 help_panel 预埋）
- [ ] 高亮组统一走 `vv-utils.hl.register` + `ColorScheme` 重挂
- [ ] spec `cmd[]` 与插件注册的 user command 同步
- [ ] 有替换主窗 buffer 行为 → 每处 displace 调 `vv-utils.bufdelete.wipe_if_throwaway`
- [ ] 涉及鼠标操作 → 遵循下方「鼠标操作规范」

---

## 鼠标操作规范

vendor 面板（vv-explorer、vv-git 等 `buftype=nofile` 的 UI buffer）需要统一处理鼠标事件，Neovim 默认行为会引起 visual 选区等问题

### 单击（左键）

用 `<LeftRelease>` 而非 `<LeftMouse>`：松开时光标已就位，避免时序问题

- **目录/可折叠行** → 单击展开/收起
- **文件/叶子行** → 不处理（让 CursorMoved preview 自动接管）
- 不映射 `<2-LeftMouse>`（双击），打开文件统一走键盘（`<CR>` / `l` / `o`）

```lua
['<LeftRelease>'] = function(s)
  local node = get_node_under_cursor(s)
  if node and node.is_dir then toggle(s) end
end,
```

### 右键

用 `<RightMouse>` + `vim.fn.getmousepos()` 手动定位光标，**不用** `<RightRelease>`（会触发 visual 模式）

```lua
['<RightMouse>'] = function(s)
  local pos = vim.fn.getmousepos()
  if pos.line > 0 then
    pcall(vim.api.nvim_win_set_cursor, s.win, { pos.line, 0 })
  end
  do_action(s)
end,
```

## 删除插件

1. 删除 `lua/plugins/specs/<category>/<id>.lua`
2. 在 [user-picks.lua](lua/plugins/manager/user-picks.lua) 删掉对应 key（非必需，孤儿 key 会被忽略）
3. 重启后 `pack/sync.lua` 自动删除磁盘上的插件目录

---

## 面板开发：清理被替换的 startup [No Name]

写「接管 / 替换主窗 buffer」的 vendor 面板时（dashboard 占主区、explorer preview、picker 切窗显示结果……），要主动清理被 displace 的 startup [No Name]，否则会持续污染 `:ls` 和 bufferline

### 根因（Neovim 默认行为，不是 bug）

`nvim` 不带文件参数启动时，必须给初始窗口挂个 buffer，于是 nvim 强制造一个空 buffer：`bufnr=1, name='', buftype='', buflisted=true, modified=false`。它和 `:enew` 出来的一模一样，nvim **不打任何特殊标记**

vim 祖传策略是「隐藏不删」——任何 `nvim_win_set_buf(win, other)` / `:edit file` 之后，原 buffer 只 hidden 不 wipe。bufferline 类插件把所有 listed buffer 都展示出来，于是 [No Name] 变成永久噪音。nvim **没有内置开关**关掉这个行为，必须在每个 displace 入口手动清

### 标准做法：`vv-utils.bufdelete.wipe_if_throwaway`

```lua
local prev_buf = vim.api.nvim_win_get_buf(target_win)
vim.api.nvim_win_set_buf(target_win, my_buf)
require('vv-utils.bufdelete').wipe_if_throwaway(prev_buf)
```

helper 走严格五重判定（`buftype=='' + name=='' + !modified + 内容空 + 不在任何窗`），全满足才 wipe。任何一条不符就跳过——不会误伤用户的 `:enew` 笔记 / dashboard / scratch / 其它 vendor 占位 buf

### 何时调

凡是用 `nvim_win_set_buf` 或 `:edit` / `:e` 替换主窗 buffer 的地方，替换之后接一下 `wipe_if_throwaway(prev_buf)`

- ✅ 必须调：preview 切换主窗 buf、`:edit file` 打开文件、dashboard 占用主窗
- ❌ 不需要调：`:vsplit` / `:tabedit` 创建**新**窗口（没替换任何 buf）；目标 buf 已经 `bufhidden=wipe`（比如 dashboard 自己的 buf 会自清）

已落地 callsite 参考：

- [vv-explorer preview.lua](https://github.com/beixiyo/vv-explorer.nvim/blob/main/lua/vv-explorer/preview.lua) — preview 替换主窗
- [vv-explorer actions/navigation.lua](https://github.com/beixiyo/vv-explorer.nvim/blob/main/lua/vv-explorer/actions/navigation.lua) — `:edit` 打开文件
- [vv-dashboard init.lua](https://github.com/beixiyo/vv-dashboard.nvim/blob/main/lua/vv-dashboard/init.lua) — dashboard 接管主窗

### 反模式

- ❌ 全局挂 `BufHidden` autocmd 自动清：触发频繁、时序复杂，可能在 buf 还没装到新窗时被误清
- ❌ 在 `VimEnter` 一次性 wipe `bufnr=1`：auto-session 等可能把它当待恢复对象
- ❌ 自己手写判定后 `nvim_buf_delete`：条件容易漏（漏掉 `win_findbuf` 检查会把别窗里的 buf 也删了），统一走 helper

显式在 displace 点清理才是可控、可预测、幂等的做法

---

## Telescope buffer_previewer + ANSI 渲染（nvim_open_term 模式）

在 telescope `new_buffer_previewer` 的 `define_preview` 中渲染 ANSI 彩色输出（如 `git show | delta`），**必须直接使用 `self.state.bufnr`**，不能自己创建 buffer

### 根因

`new_buffer_previewer` 的 `preview_fn`（[buffer_previewer.lua:421](https://github.com/nvim-telescope/telescope.nvim/blob/master/lua/telescope/previewers/buffer_previewer.lua)）流程：

1. **创建新 buffer**：每次调用 `preview_fn`（无 `get_buffer_by_name` 时），telescope 都 `nvim_create_buf` 并赋给 `self.state.bufnr`
2. **`vim.schedule` 设窗口 buffer**：`vim.schedule(function() win_set_buf(preview_winid, bufnr) end)` — 注意 `bufnr` 是**闭包局部变量**，不是 `self.state.bufnr`
3. **调用 `define_preview`**
4. **schedule 执行**：`define_preview` 返回后，scheduled 回调把 telescope 的 `bufnr` 放进预览窗口

### 反模式（全部踩过）

| 做法 | 为什么不行 |
|------|-----------|
| 自己 `nvim_create_buf` + `nvim_win_set_buf` | telescope 的 schedule 会把它自己的 buffer 放回去，覆盖你的 |
| 改 `self.state.bufnr` 指向自己的 buffer | schedule 闭包捕获的是**局部变量**，不读 `self.state.bufnr` |
| 删掉 telescope 的 buffer 再自己设 | schedule 的 `nvim_buf_is_valid` 检查失败 → 跳过 → 窗口显示的还是旧 buffer |

### 正确模式

```lua
opts.previewer = previewers.new_buffer_previewer({
  define_preview = function(self, entry)
    -- telescope 每次已创建新 buffer，直接用
    local bufnr = self.state.bufnr
    local chan = vim.api.nvim_open_term(bufnr, {})

    vim.fn.jobstart({ 'bash', '-c', 'git show --color=always ' .. entry.value .. ' | delta' }, {
      stdout_buffered = true,
      on_stdout = function(_, data)
        if not vim.api.nvim_buf_is_valid(bufnr) then return end
        vim.api.nvim_chan_send(chan, table.concat(data, '\r\n'))
      end,
    })
  end,
})
```

**要点**：

- `nvim_open_term(self.state.bufnr)` 每次都在新鲜 buffer 上调用，不会重复
- telescope 的 schedule 会把这个 buffer（已变为 terminal + 有数据）放进窗口 — 正好是我们要的
- 不需要自己 `nvim_create_buf`、不需要 `nvim_win_set_buf`、不需要 `nvim_buf_delete`
- `stdout_buffered = true` 确保数据一次性到达，避免流式 schedule 乱序
- scrollback hack（`vim.bo[bufnr].scrollback = 9999; vim.bo[bufnr].scrollback = 9998`）强制 terminal buffer 刷新渲染
- C-e/C-y 滚动由 telescope defaults 的 `scroll_previewer` 处理，虚拟终端 buffer 可正常滚动

**落地参考**：[lua/plugins/specs/ui/telescope/git_log.lua](lua/plugins/specs/ui/telescope/git_log.lua)

---

## 常见坑

- **`main` 推断不出**：多 lua 子目录 + normname 不匹配（如 `blink.cmp` 仓库的 `lua/blink/` 推不到 `blink.cmp`），显式写 `main = 'blink.cmp'`
- **`main` 推断错**：有唯一 lua 子目录但不是想要的（如只有 `lua/blink/` 却想要 `blink.cmp`），同样显式写
- **克隆不完整**：[loader.lua](lua/pack/loader.lua) 检测到 `.git` 之外无可见文件会自动清理，重启再装即可
- **依赖顺序**：`dependencies` 里的仓库会在主插件前 `packadd`；依赖自己也需要 setup 时，为它单独建一个 spec
- **Prompt 重复下载**：同一 URL 在多个插件的 `dependencies` 中出现会被去重（见 `unique_active`）
- **`lazy = 'manual'` 的 config 签名**：启动期 `config(plugin, { load = fn })`，第 2 参数是 ctx 不是 opts；loader 里会对 `lazy == 'manual'` 的 spec **早退**不再跑 config，避免 ctx 被二次覆盖
- **config 签名**：普通 spec 是 `config(plugin, opts)` 对齐 lazy.nvim；需要 plugin 主模块时在函数内 `require('xxx')` 自取
- **Neovim 版本**：`vim.pack` 需要 0.12+，否则 [pack/init.lua](lua/pack/init.lua) 会直接报错退出

## 冒烟测试

```vim
:lua require('pack.smoke').run()
```

输出内容包括：模块加载、spec 扫描统计、spec 结构校验、user-picks 状态。新增或修改 spec 后建议跑一遍
