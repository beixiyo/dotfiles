-- vv-mcp.nvim — 向外部 AI 暴露当前 Neovim 实例及原生 LSP 能力
-- 本地开发：vendors/vv-mcp.nvim（pack.dev 自动重定向）
---@type PackSpec
  return {
    desc = '通过 MCP 暴露 Neovim 实例与 LSP 能力',
    url = 'beixiyo/vv-mcp.nvim',
    main = 'vv-mcp',
    dependencies = { 'beixiyo/vv-utils.nvim' },

    opts = {
      -- server = {
      --   path = vim.fn.stdpath('config')
      --     .. '/vendors/vv-mcp.nvim/target/debug/vv-mcp',
      -- },
    },
  }

