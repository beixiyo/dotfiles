# AGENTS.md — Neovim 配置开发入口

本文只定义 `.config/nvim` 的全局边界和文档索引。具体机制由 owning 模块的 README 维护，修改前先读取离目标最近的文档

## 项目事实

- 要求 Neovim 0.12+，插件管理基于原生 `vim.pack`
- 入口：`init.lua` → `config.options` → `config.neovide` → `config.clipboard` → `pack` → `config.keymaps` → `config.autocmd` → `config.cmd`
- 插件声明位于 `lua/plugins/specs/`，按 `code` / `tools` / `ui` 分类
- 插件管理器机制位于 `lua/pack/`
- 自研、fork 和离线插件源码位于根目录 `vendors/`，其中 `vv-*.nvim` 通常是独立 Git 仓库
- `.luarc.json` 的库路径由 `bun run scripts/gen-luarc.ts` 生成

## 修改前按目标读取

- 修改插件 spec 或 pack 引擎：读 [lua/pack/README.md](lua/pack/README.md)
- 修改任意 `vv-*` 插件：读 [vendors/AGENTS.md](vendors/AGENTS.md)
- 查共享能力和当前 API：读 [vv-utils 中文 README](vendors/vv-utils.nvim/README.zh-CN.md)
- 修改空 buffer 清理：读 [vv-utils bufdelete 边界](vendors/vv-utils.nvim/docs/bufdelete.md)
- 修改 Telescope ANSI/terminal preview：读 [Telescope spec README](lua/plugins/specs/ui/telescope/README.md)
- 修改具体 vendor：继续读取该仓库自己的 `AGENTS.md` / `README.md`

不要把下游模块的完整 API 表复制回本文件；这里保持索引和跨模块边界

## 插件 spec 最小示例

新建 `lua/plugins/specs/<category>/<id>.lua`，或需要辅助模块时使用 `<category>/<id>/init.lua`：

```lua
return {
  desc = '显示在 PluginManager 的描述',
  url = 'author/my-plugin',
  cmd = { 'MyPluginOpen' },
  keys = {
    {
      '<leader>mp',
      '<cmd>MyPluginOpen<cr>',
      mode = 'n',
      desc = 'My Plugin',
    },
  },
  opts = {
    enabled = true,
  },
}
```

关键默认值：

- `id` 默认取 spec 文件或目录名
- `category` 默认取 `code` / `tools` / `ui`
- `keys[].mode` 默认只包含 normal mode；visual 或 operator-pending 必须显式声明
- 没写 `config` 时自动调用 `require(main).setup(opts)`
- `main = false` 表示不 require 主模块
- `priority` 默认 0，按降序加载
- VSCode-Neovim 中 `loadInVSCode` 默认 false

完整字段、懒加载、dev redirect、build 和命令契约只在 [lua/pack/README.md](lua/pack/README.md) 维护

## 全局设计边界

- pack 模块提供插件加载机制，spec 决定具体插件策略
- vendor 先复用 `vv-utils`，但不为假想 caller 抽象
- 异步任务优先复用 `vv-utils.async` 管理 latest-wins、物理取消、资源释放和过期回调；资源仍由创建它的模块在切换或关闭时释放
- 全局快捷键放 spec `keys`；buffer-local 交互由 owning 插件注册
- UI 配色优先使用 `require('tools.palette')`，不要在多个 spec 散落相同色值

## Loading / 骨架规范

统一基于 `vv-utils.loading`，API 与边界见 [loading README](vendors/vv-utils.nvim/lua/vv-utils/loading/README.md)，落点决策案例见 [LOADING_AUDIT](vendors/LOADING_AUDIT.md)

- **何时加**：按键后要等可感知的异步操作（git / LSP / 网络 / 大目录 IO / 外部进程）且界面看不出已生效或显示陈旧内容；同步瞬时操作不加。可能很快完成的操作设 `delay_ms`（常用 150）避免闪烁
- **落点**：放在用户视线所在、不会被截掉的位置，优先级依次为
  1. 行内贴近对象：名字后 `pos = 'inline'`；名字前固定宽度槽（图标、折叠箭头）`pos = 'overlay'` + `width` 补齐，不挤动文字
  2. 没有可锚定行的浮窗：`win_text` 写 title / footer
  3. Telescope：结果窗标题（`results_border:change_title` + `ticker`）或预览骨架（先写灰色 `Loading…`，首个 stdout 到达时清屏）
  4. 无任何界面且同步阻塞：`blocking` 的 echo
- **禁止长行行尾**：`eol` / `right_align` 只用于短且固定的行（空状态、短 header）；面板窄、代码行不折行，长行 eol 必被截掉（vv-git worktree 删除的教训）
- **选型**：单一位置用 `mark`；浮窗边框用 `win_text`；需拼进复合 UI（prompt、Telescope 标题）用 `ticker`；同一位置多个并发 / latest-wins 请求用 `slot` 引用计数；多行同时在途用一个 `mark` 的 `get_pos` 返回数组；同步阻塞用 `blocking`。不要自建 uv timer，全部走共享时钟
- **生命周期**：stop / release 挂在请求终结（`vv-utils.async` 的 disposer：finish / cancel / dispose 都会调用）上，不能只挂成功回调；`stop()` 幂等。latest-wins 下旧请求终结不得停掉新请求的显示（用 `slot`）。帧持续到结果真正渲染为止（如 stage 写入成功后等随后发起的 reload 渲染完），失败立即撤掉。`get_pos` 每帧重新定位，目标不在时返回 nil 隐藏；buffer wipe / 窗口关闭自动停止，`ticker` 由调用方负责停止
- **视觉**：帧与 label 分开上色，默认 `VVLoading`（蓝 `#7aa2f7`）与 `VVLoadingLabel`（link `Comment`），不要硬编码色值；同一窗口同一槽位不叠加多个 `win_text`
- **不阻塞主线程**：同步阻塞期间帧不会推进。长任务必须异步化，大量 IO 用 uv timer 分片让出（参考 `vv-utils.fs.delete_async`），不用 `vim.schedule` 自递归

## 常用命令

- `tests/run.sh [过滤词]`：一键跑全部测试（等价 `nvim -l tests/run.lua`；递归 `tests/**/test_*.lua`，每文件独立子进程，失败隔离；退出码非 0 = 有失败，幂等可重复跑）
- 新增测试：放 `tests/<分类>/test_*.lua`，样板 `dofile(vim.fs.find('harness.lua', { upward = true, ... })[1])` 取得断言 / git fixture / notify 捕获 / wait；失败消息写被破坏的契约；清理必须包进 `with_git_repo` 或 pcall 保证失败路径也执行
- headless 测试只覆盖数据与异步逻辑；keymap、preview 滚动、telescope UI 交互仍需完整配置手动验证
- `:PluginManager` / `<leader>fp`：插件管理 UI
- `:PackUpdate [name ...]`：更新全部或指定插件
- `:PackDev [name]`：查看本地开发重定向
- `:PackStats`：加载性能 UI
- `:PackStatsEcho`：在消息中输出加载统计
- `:PackGenTypes`：重新生成 Lua library 类型路径

## 验证

修改 spec 或 pack 后运行：

```vim
:lua require('pack.smoke').run()
```

smoke 只验证模块可加载、spec 可扫描、结构合法和 user-picks 可读取，不证明插件真实交互有效

涉及 keymap、窗口、鼠标、snippet、异步 LSP 或插件生命周期时，还必须在完整配置和真实 buffer 中验证；headless 结果不能替代用户交互

异步生命周期改动至少验证：旧任务被取消、旧回调不写回，以及关闭后不重建 UI
