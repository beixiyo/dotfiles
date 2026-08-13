-- Flash：搜索标签跳转
-- keys 直接声明最终 rhs，首次按下触发加载即执行真实逻辑；which-key 启动期可见 desc
---@module 'flash'
---@type PackSpec
return {
  desc = '快速跳转',
  url = 'https://github.com/folke/flash.nvim',
  main = 'flash',
  dependencies = { 'beixiyo/vv-icons.nvim' },
  loadInVSCode = true,

  keys = function()
    local icons = require('vv-icons')
    return {
      { 's', function() require('flash').jump() end, mode = { 'n', 'x', 'o' }, desc = icons.jumps .. ' Flash jump' },
      { 'S', function() require('flash').treesitter() end, mode = { 'n', 'x', 'o' }, desc = icons.vscode .. ' Flash Treesitter' },
      { 'f', nil, mode = { 'n', 'x', 'o' }, desc = icons.jumps .. ' Flash f' },
      { 'F', nil, mode = { 'n', 'x', 'o' }, desc = icons.jumps .. ' Flash F' },
      { '/', nil, mode = 'n', desc = icons.jumps .. ' Flash search forward' },
      { '?', nil, mode = 'n', desc = icons.jumps .. ' Flash search backward' },
    }
  end,

  ---@type Flash.Config
  opts = {
    search = { mode = 'fuzzy' },
    highlight = { backdrop = false },
    jump = { autojump = true },
    label = {
      style = 'overlay',
      rainbow = { enabled = true, shade = 5 },
    },
    modes = {
      search = { enabled = true },
      char = {
        jump_labels = true,
        multi_line = true,
        keys = { 'f', 'F' },
        highlight = { backdrop = false, matches = true },
      },
      treesitter = {
        labels = 'asdfghjklqwertyuiopzxcvbnm',
        label = { rainbow = { enabled = true, shade = 5 } },
      },
    },
  },

  ---@param _ PackSpec
  ---@param opts Flash.Config
  config = function(_, opts)
    require('flash').setup(opts)
    vim.api.nvim_set_hl(0, 'FlashLabel', { bold = true })
  end,
}
