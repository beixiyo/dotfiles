-- vv-translate.nvim — 面向代码标识符和 Visual 选区的翻译浮窗
---@type PackSpec
return {
  desc = '代码标识符与选区翻译浮窗',
  url = 'beixiyo/vv-translate.nvim',
  main = 'vv-translate',
  dependencies = { 'beixiyo/vv-utils.nvim' },
  cmd = { 'VVTranslate', 'VVTranslateWord', 'VVTranslateVisual', 'VVTranslateClose' },
  keys = {
    {
      '<leader>tw',
      '<cmd>VVTranslate<cr>',
      mode = { 'n', 'x' },
      desc = '󰊿 Translate text',
    },
  },
  opts = {},
}
