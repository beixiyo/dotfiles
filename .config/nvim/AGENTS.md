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
- 资源所有者负责 timer、autocmd、listener、buffer 和 window 的清理
- 异步回调在写回前检查 buffer/window 是否仍有效，并防止过期结果覆盖新状态
- 全局快捷键放 spec `keys`；buffer-local 交互由 owning 插件注册
- UI 配色优先使用 `require('tools.palette')`，不要在多个 spec 散落相同色值

## 常用命令

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
