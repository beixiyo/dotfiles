-- Language server 配置入口
-- Mason server 自动启用；TypeScript 与 Tailwind 由 mise 管理，需要在配置后手动 enable

local M = {}

function M.setup()
  require('plugins.specs.code.lsp.servers.lua_ls').setup()
  require('plugins.specs.code.lsp.servers.mason').setup()
  require('plugins.specs.code.lsp.servers.tsc').setup()
  require('plugins.specs.code.lsp.servers.tailwindcss').setup()

  vim.lsp.enable({ 'tsc', 'tailwindcss' })
end

return M
