-- 彩虹括号 - 多层括号配对着色（基于 treesitter）

-- 超过该行数的 buffer 不启用彩虹括号
local MAX_LINES = 10000

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
      -- global strategy 首次 attach 会对全文件逐个括号 vim.hl.range，3 万行级约 1.3s；
      -- vv-git diff 每次 preview 新建 scratch 都会重付这笔成本，因此大 buffer 不 attach
      condition = function(buf)
        return vim.api.nvim_buf_line_count(buf) < MAX_LINES
      end,
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
