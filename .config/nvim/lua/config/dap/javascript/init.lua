-- JavaScript、TypeScript、Bun、浏览器与 Electron 调试入口
local adapter = require('config.dap.javascript.adapter')
local browser = require('config.dap.javascript.browser')
local electron = require('config.dap.javascript.electron')
local node = require('config.dap.javascript.node')
local package_script = require('config.dap.javascript.package-script')

local M = {}

---@param dap table
function M.setup(dap)
  adapter.setup(dap)

  -- 跳过 Node 内置模块和包依赖，避免单步调试进入第三方源码
  local skip_files = {
    '<node_internals>/**',
    '**/node_modules/**',
    -- Vite React Refresh 注入的虚拟运行时源码
    '**/@react-refresh*',
  }

  -- JS、TS、JSX、TSX 都可能运行在 Main 或 Renderer，不能用 filetype 猜进程归属
  local configurations = node.configurations(skip_files)
  vim.list_extend(configurations, package_script.configurations(skip_files))
  vim.list_extend(configurations, browser.configurations(skip_files))
  vim.list_extend(configurations, electron.node_configurations(skip_files))
  vim.list_extend(configurations, electron.browser_configurations(skip_files))

  for _, filetype in ipairs({ 'javascript', 'typescript', 'javascriptreact', 'typescriptreact' }) do
    dap.configurations[filetype] = configurations
  end
end

return M
