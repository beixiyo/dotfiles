-- conform.nvim：格式化编排
-- JSON/Markup/CSS/Markdown → dprint；JS/TS → 项目本地 Oxlint 修复后 dprint；其余走 LSP fallback
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

  opts = function()
    return {
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
        typescript = { 'oxlint', 'dprint' },
        typescriptreact = { 'oxlint', 'dprint' },
        javascript = { 'oxlint', 'dprint' },
        javascriptreact = { 'oxlint', 'dprint' },
      },
      formatters = {
        -- Conform 内置 oxlint 会回退到 PATH；这里明确禁止全局回退，只接受项目依赖
        oxlint = {
          command = require('conform.util').find_executable({ 'node_modules/.bin/oxlint' }, ''),
          args = { '--fix', '$FILENAME' },
        },
      },
    }
  end,

  config = function(_, opts)
    require('conform').setup(opts)
  end,
}
