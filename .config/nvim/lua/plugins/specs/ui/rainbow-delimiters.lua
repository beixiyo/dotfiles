-- 彩虹括号 - 多层括号配对着色（基于 treesitter）
---@type PackSpec
return {
  desc = '彩虹括号',
  url = 'https://github.com/HiPhish/rainbow-delimiters.nvim',
  main = 'rainbow-delimiters',
  dependencies = { 'https://github.com/nvim-treesitter/nvim-treesitter' },
  event = { 'BufReadPost', 'BufNewFile' },

  config = function()
    local rd = require('rainbow-delimiters')
    -- VSCode 默认配色（editorBracketHighlight）：3 色循环
    vim.api.nvim_set_hl(0, 'RainbowDelimiterYellow', { fg = '#FFD700' })
    vim.api.nvim_set_hl(0, 'RainbowDelimiterViolet', { fg = '#DA70D6' })
    vim.api.nvim_set_hl(0, 'RainbowDelimiterBlue',   { fg = '#179FFF' })
    vim.api.nvim_set_hl(0, 'RainbowDelimiterRed',    { fg = '#FF1212', bg = '#3A0000', bold = true })

    ---@type rainbow_delimiters.config
    vim.g.rainbow_delimiters = {
      strategy = {
        [''] = rd.strategy['global'],
        vim = rd.strategy['local'],
      },
      query = {
        [''] = 'rainbow-delimiters',
        lua = 'rainbow-blocks',
        tsx = 'rainbow-parens',
        javascript = 'rainbow-delimiters-react',
      },
      highlight = {
        'RainbowDelimiterYellow',
        'RainbowDelimiterViolet',
        'RainbowDelimiterBlue',
      },
    }
  end,
}
