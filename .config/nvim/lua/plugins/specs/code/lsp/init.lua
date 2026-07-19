-- LSP 与代码诊断
--
--   watchfiles.lua  —— 修复工作区根落到 $HOME 时 inotify 配额被打爆
--   servers.lua     —— Mason 安装 / server 定义 / vim.lsp.enable
--   diagnostics.lua —— 诊断外观（sign icon、virtual_text、悬浮窗）
--   symbols.lua     —— gO 全局符号、go 文档符号（无 LSP 时降级 treesitter）
--   keymaps.lua     —— LspAttach 后的 buffer 级键位
--
-- 架构（Neovim 0.11+ 原生范式）：
--   1. mason.nvim           —— 安装 LSP / formatter 二进制（:Mason 面板）
--   2. mason-lspconfig.nvim —— 桥接层：Mason 装了什么就自动 vim.lsp.enable() 什么
--   3. nvim-lspconfig       —— 提供 ~300 个 server 的默认配置
--   4. vim.lsp.enable()     —— 按需启停 client、自动 attach/detach
--
-- 不能 lazy 加载：mason-lspconfig.automatic_enable 内部 vim.lsp.enable() 注册 FileType
-- 是异步/延迟的，BufReadPre 触发时会错过当前 buffer 的 FileType（auto-session 恢复尤其明显）
---@type PackSpec
return {
  desc = 'LSP 与代码诊断',
  url = 'https://github.com/neovim/nvim-lspconfig',
  main = 'lspconfig',
  dependencies = {
    'https://github.com/mason-org/mason.nvim',
    'https://github.com/mason-org/mason-lspconfig.nvim',
    'beixiyo/vv-icons.nvim',
  },

  config = function()
    -- 顺序有意义：watchfiles 的猴补丁要赶在任何 client 启动前打上；
    -- keymaps 依赖 symbols 导出的 open_workspace_symbols
    require('plugins.specs.code.lsp.watchfiles').setup()
    require('plugins.specs.code.lsp.servers').setup()
    require('plugins.specs.code.lsp.diagnostics').setup()
    require('plugins.specs.code.lsp.symbols').setup()
    require('plugins.specs.code.lsp.keymaps').setup()
  end,
}
