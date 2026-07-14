-- 智能注释：mini.comment + ts-context-commentstring
-- main 指向 ts_context_commentstring：loader 默认先 require 它做 setup，再自己配 mini.comment
---@type PackSpec
return {
  desc = '智能行/块注释（含 TSX 支持）',
  url = 'https://github.com/nvim-mini/mini.comment',
  main = 'ts_context_commentstring',
  dependencies = { 'https://github.com/JoosepAlviste/nvim-ts-context-commentstring' },

  config = function()
    require('ts_context_commentstring').setup({ enable_autocmd = false })

    require('mini.comment').setup({
      options = {
        custom_commentstring = function()
          return require('ts_context_commentstring.internal').calculate_commentstring() or vim.bo.commentstring
        end,
      },
    })
  end,
}
