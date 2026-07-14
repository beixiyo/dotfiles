-- 光标词高亮（LSP / treesitter / regex 三层 fallback）
---@type PackSpec
return {
  desc = '光标词高亮',
  url = 'https://github.com/RRethy/vim-illuminate',
  main = 'illuminate',
  event = { 'BufReadPost', 'BufNewFile' },

  config = function()
    local illuminate = require('illuminate')
    illuminate.configure({
      providers = { 'lsp', 'treesitter', 'regex' },
      delay = 100,
      min_count_to_highlight = 2,
      large_file_cutoff = 2000,
      large_file_overrides = { providers = { 'lsp' } },
      filetypes_denylist = { 'dirvish', 'fugitive', 'dashboard', 'file-tree' },
    })

    -- ]] / [[ 引用导航
    vim.keymap.set('n', ']]', function() illuminate.goto_next_reference() end, { desc = 'Next reference' })
    vim.keymap.set('n', '[[', function() illuminate.goto_prev_reference() end, { desc = 'Previous reference' })
  end,
}
