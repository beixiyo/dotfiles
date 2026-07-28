# Pack 引擎契约

本文是 `.config/nvim/lua/pack` 的 owner 文档，描述当前 `PackSpec`、加载阶段、命令和验证方式。实现变化时同步更新本文件

## 处理流程

1. `scan.collect()` 扫描 `lua/plugins/specs/<category>/<id>.lua` 和 `<id>/init.lua`
2. 路径补齐 `id`、`category`，同名时目录 spec 优先
3. `dev.redirect()` 在下载前把匹配的远程 spec 重定向到 `vendors/`
4. 根据 user-picks、VSCode 白名单和 `cond` 分成 active/disabled
5. URL 去重后调用 `vim.pack.add`
6. spec 按 `priority` 降序分发到 eager、声明式 lazy 或 manual
7. `loader.load()` 依次处理 rtp、build、init、dependencies、packadd、main、opts 和 config

## Spec 字段

| 字段 | 契约 |
|---|---|
| `desc` | PluginManager 描述；项目规范要求填写，引擎类型仍允许缺省 |
| `url` / `dir` | 二选一；smoke 会拒绝同时存在或同时缺失 |
| `main` | 主 Lua 模块；缺省时按仓库名和 `lua/` 顶层目录推断；`false` 跳过 require |
| `id` / `category` | 缺省时由路径补齐 |
| `name` | 覆盖 `packadd` 名称 |
| `dependencies` | URL 字符串或 `{ src, version? }` 数组；先于主插件 `packadd` |
| `priority` | 默认 0，数值越大越早分发 |
| `init` | `function(plugin)`，在主插件 `packadd` 前执行 |
| `opts` | table 或 `function(plugin): table` |
| `config` | `function(plugin, opts)`；缺省时调用 `require(main).setup(opts)` |
| `build` | Ex 命令字符串、shell 命令字符串或 argv 字符串数组 |
| `version` / `branch` / `tag` / `commit` | 按 `commit > tag > version > branch` 归一化到 `vim.pack.Spec.version` |
| `cond` | false 或返回 false 的函数会禁用 spec |
| `loadInVSCode` | VSCode-Neovim 白名单，默认 false |
| `dev` | true 强制尝试本地，false 禁止自动本地重定向 |

`vim.pack.Spec.version` 接受 branch、tag、commit 字符串或 `vim.VersionRange`。已有插件不会因再次 `vim.pack.add` 自动切到新 revision，需要执行 `vim.pack.update`

## 懒加载字段

- `event`: 字符串或数组；支持 `Event pattern` 形式
- `ft`: FileType 字符串或数组
- `cmd`: 首次调用占位命令时加载，再通过 `nvim_cmd` 结构化重放
- `keys`: table 或 `function(plugin): table`
- `lazy = 'manual'`: 启动期调用 `config(plugin, { load = fn })`，由 spec 决定何时执行真实加载

`keys` 条目格式：

```lua
{
  '<leader>x',
  '<cmd>Example<cr>',
  mode = 'n',
  desc = 'Example',
  ft = 'lua',
  expr = false,
  nowait = false,
  silent = true,
  remap = false,
}
```

边界：

- `mode` 默认只包含 `'n'`
- `ft` 会创建 buffer-local 占位映射
- rhs 缺省时，加载后由插件自己的映射接管
- rhs 为 `'<Nop>'` 或空串时直接安装真实映射，不触发加载
- 首次触发会删除占位、加载插件、安装真实 rhs，再以 `<Ignore>` 前缀重放 lhs

## 本地开发重定向

`dev.lua` 默认在 `vendors/` 查找 URL 命中 `beixiyo` 的同名仓库：

- 自动命中且本地存在：`url` 转为 `dir`
- 自动命中但本地不存在：按 `fallback` 回退远程或跳过
- `dev = true`：强制尝试本地，缺失时给出警告
- `dev = false`：即使命中 pattern 也保持远程
- 原 URL 保存在 `_dev_origin_url`

使用 `:PackDev` 查看全部重定向，或 `:PackDev <name>` 查看单项判定

## Build

- `':Command'`：在 schedule 中先 `packadd`，再执行 Ex 命令
- `'command --flag'`：按空白拆成 argv 后交给 `vim.system`
- `{ 'command', '--flag' }`：直接作为 argv，涉及空格或复杂参数时优先使用

成功后在插件目录写 `.build_done`。`PackChanged` 的 install/update 会删除标记并重跑 build

shell 字符串不会经过 shell 解析，因此不要依赖管道、重定向、引号展开或环境变量展开；需要这些能力时使用显式可执行脚本

## 命令

- `:PackUpdate [name ...]`
- `:PackStats`
- `:PackStatsEcho`
- `:PackDev [name]`
- `:PackGenTypes`
- `:PluginManager`

## 验证

```vim
:lua require('pack.smoke').run()
```

smoke 是静态结构检查。修改 lazy keymap、command replay、build 或更新生命周期时，还需调用相应生产入口验证真实行为
