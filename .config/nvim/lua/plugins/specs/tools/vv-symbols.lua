-- 基于 LSP 的符号树、实时筛选与函数上方引用提示
---@type PackSpec
return {
  desc = 'LSP 符号浏览、实时筛选与引用提示',
  dir = vim.fn.stdpath('config') .. '/vendors/vv-symbols.nvim',
  main = 'vv-symbols',
  dependencies = { 'beixiyo/vv-utils.nvim' },
  event = { 'UIEnter', 'LspAttach' },
  cmd = {
    'VVSymbolsOpen',
    'VVSymbolsClose',
    'VVSymbolsToggle',
    'VVSymbolsFilter',
    'VVSymbolsRefresh',
    'VVSymbolsReferences',
    'VVSymbolsPeek',
    'VVSymbolsLensEnable',
    'VVSymbolsLensDisable',
    'VVSymbolsEnable',
    'VVSymbolsDisable',
    'VVSymbolsDiagnostics',
    'VVSymbolsQuickfix',
    'VVSymbolsLoclist',
  },
  opts = function()
    return {
      panel = { state = require('vv-utils.state').register('vv-symbols', 'panel') },
    }
  end,
  keys = function()
    local icons = require('vv-icons')
    return {
      {
        '<leader>xx',
        function() require('vv-symbols').diagnostics({ buf = 0, toggle = true }) end,
        desc = icons.list .. ' Buffer diagnostics',
      },
      {
        '<leader>xX',
        function() require('vv-symbols').diagnostics({ toggle = true }) end,
        desc = icons.list .. ' Workspace diagnostics',
      },
      {
        '<leader>xq',
        function() require('vv-symbols').quickfix({ toggle = true }) end,
        desc = icons.list .. ' Quickfix',
      },
      {
        '<leader>xQ',
        function()
          vim.fn.setqflist({}, 'r', {})
          require('vv-symbols').close()
        end,
        desc = icons.list .. ' Clear quickfix',
      },
    }
  end,
}
