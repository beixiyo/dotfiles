-- JavaScript、TypeScript、Bun 与浏览器调试配置
local browser_url = require('config.dap.url')

local M = {}

---@param dap table
function M.setup(dap)
  -- vscode-js-debug 由独立插件配置构建，这里复用其 DAP server 支持 Node、Bun 和 Chrome
  local function get_adapter_path()
    local root = require('pack.spec').get_root('vscode-js-debug')
    local path = root and (root .. '/dist/src/dapDebugServer.js') or nil

    return path and vim.fn.filereadable(path) == 1 and path or nil
  end

  local function js_adapter(callback, config)
    local adapter_path = get_adapter_path()
    if not adapter_path then
      vim.notify('vscode-js-debug is still building; retry when Pack build completes', vim.log.levels.WARN)
      return
    end

    local port = config.port or '${port}'
    callback({
      type = 'server',
      host = '127.0.0.1',
      port = port,
      executable = {
        command = 'node',
        args = { adapter_path, port, '127.0.0.1' },
      },
    })
  end

  dap.adapters['pwa-node'] = js_adapter
  dap.adapters['pwa-chrome'] = js_adapter

  -- 跳过 Node 内置模块和 pnpm/npm 依赖，避免单步调试进入 React 等第三方源码
  local js_skip_files = {
    '<node_internals>/**',
    '**/node_modules/**',
  }

  local node_configs = {
    {
      type = 'pwa-node',
      request = 'launch',
      name = 'Launch current file',
      program = '${file}',
      cwd = '${workspaceFolder}',
      sourceMaps = true,
      skipFiles = js_skip_files,
      console = 'integratedTerminal',
    },
    {
      type = 'pwa-node',
      request = 'attach',
      name = 'Attach to process',
      processId = require('dap.utils').pick_process,
      cwd = '${workspaceFolder}',
      sourceMaps = true,
      skipFiles = js_skip_files,
    },
    {
      type = 'pwa-node',
      request = 'launch',
      name = 'Launch current file with Bun',
      runtimeExecutable = 'bun',
      runtimeArgs = { 'run' },
      program = '${file}',
      cwd = '${workspaceFolder}',
      sourceMaps = true,
      skipFiles = js_skip_files,
      console = 'integratedTerminal',
    },
  }

  dap.configurations.javascript = node_configs
  dap.configurations.typescript = node_configs

  local browser_configs = {
    {
      type = 'pwa-chrome',
      request = 'launch',
      name = 'Launch browser',
      url = browser_url.prompt,
      webRoot = '${workspaceFolder}',
      sourceMaps = true,
      skipFiles = js_skip_files,
    },
  }

  dap.configurations.javascriptreact = browser_configs
  dap.configurations.typescriptreact = browser_configs
end

return M
