-- gopls 默认不返回任何 inlay hint，需要逐项声明；是否显示由 <leader>ch 控制（见 lsp/keymaps.lua）

local M = {}

function M.setup()
  vim.lsp.config('gopls', {
    settings = {
      gopls = {
        hints = {
          assignVariableTypes = true,
          compositeLiteralFields = true,
          compositeLiteralTypes = true,
          constantValues = true,
          functionTypeParameters = true,
          parameterNames = true,
          rangeVariableTypes = true,
        },
      },
    },
  })
end

return M
