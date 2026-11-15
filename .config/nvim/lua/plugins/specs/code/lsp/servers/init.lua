-- Language server 配置入口
-- Mason server 自动启用；TypeScript 与 Tailwind 由 mise 管理，需要在配置后手动 enable

local M = {}

function M.setup()
  require('plugins.specs.code.lsp.servers.lua_ls').setup()
  require('plugins.specs.code.lsp.servers.cssls').setup()
  require('plugins.specs.code.lsp.servers.gopls').setup()
  require('plugins.specs.code.lsp.servers.jsonls').setup()
  require('plugins.specs.code.lsp.servers.yamlls').setup()
  require('plugins.specs.code.lsp.servers.vue').setup()
  require('plugins.specs.code.lsp.servers.mason').setup()
  local typescript_server = require('plugins.specs.code.lsp.servers.tsc').setup()
  require('plugins.specs.code.lsp.servers.tailwindcss').setup()

  vim.lsp.enable({ typescript_server, 'tailwindcss' })
end

return M
