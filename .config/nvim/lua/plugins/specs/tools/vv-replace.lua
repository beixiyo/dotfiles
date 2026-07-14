-- vv-replace.nvim — VSCode 风的搜索替换面板（自实现，仅依赖 ripgrep）
---@type PackSpec
return {
  desc = '搜索替换（VSCode 风）',
  url  = 'beixiyo/vv-replace.nvim',
  main = 'vv-replace',
  dependencies = { 'beixiyo/vv-icons.nvim' },

  cmd = { 'VVReplace', 'VVReplaceFile', 'VVReplaceClose', 'VVReplaceToggle' },
  keys = function()
    local icon = require('vv-icons').find_text .. ' '
    return {
    -- normal：当前文件 / 工作区
      { '<leader>sr', '<cmd>VVReplaceFile<cr>', mode = 'n', desc = icon .. 'Replace in file' },
      { '<leader>sR', '<cmd>VVReplace<cr>',     mode = 'n', desc = icon .. 'Replace in workspace' },

    -- visual：选区语义全交给插件 open_visual 封装（use=query 选区作搜索词 / use=range 选区作替换范围）
      { '<leader>sr', function() require('vv-replace').open_visual({ scope = 'file', use = 'query' }) end, mode = 'v', desc = icon .. 'Replace selection in file' },
      { '<leader>sR', function() require('vv-replace').open_visual({ use = 'query' }) end,                 mode = 'v', desc = icon .. 'Replace selection in workspace' },
      { '<leader>sv', function() require('vv-replace').open_visual({ scope = 'file', use = 'range' }) end, mode = 'v', desc = icon .. 'Replace within selection' },
    }
  end,

  ---@type VVReplaceConfig
  opts = {},
}
