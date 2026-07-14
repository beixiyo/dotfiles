-- conform.nvim：格式化编排
-- JSON/Markup/CSS/Markdown/TS/TSX/JS/JSX → dprint，其余走 LSP fallback
---
-- dprint 全局配置在 ~/.config/dprint/dprint.json
---@type PackSpec
return {
  desc = '格式化编排（dprint + LSP fallback）',
  url = 'https://github.com/stevearc/conform.nvim',
  dependencies = { 'beixiyo/vv-icons.nvim' },

  keys = function()
    return {
      {
        '<leader>cf',
        function()
          require('conform').format({ async = true, lsp_format = 'fallback' })
        end,
        desc = require('vv-icons').fix .. ' Format',
        mode = { 'n', 'x' },
      },
    }
  end,

  opts = {
    formatters_by_ft = {
      json = { 'dprint' },
      jsonc = { 'dprint' },
      xml = { 'dprint' },
      svg = { 'dprint' },
      html = { 'dprint' },
      css = { 'dprint' },
      scss = { 'dprint' },
      less = { 'dprint' },
      markdown = { 'dprint' },
      yaml = { 'dprint' },
      toml = { 'dprint' },
      typescript = { 'dprint' },
      typescriptreact = { 'dprint' },
      javascript = { 'dprint' },
      javascriptreact = { 'dprint' },
    },
  },

  config = function(_, opts)
    require('conform').setup(opts)
  end,
}
