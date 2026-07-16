-- vscode-js-debug adapter 注册
local M = {}

---@param dap table
function M.setup(dap)
  -- vscode-js-debug 由独立插件配置构建，这里只负责接入其 DAP server
  local function get_adapter_path()
    local root = require('pack.spec').get_root('vscode-js-debug')
    local path = root and (root .. '/dist/src/dapDebugServer.js') or nil

    return path and vim.fn.filereadable(path) == 1 and path or nil
  end

  local function js_adapter(callback)
    local adapter_path = get_adapter_path()
    if not adapter_path then
      vim.notify('vscode-js-debug is still building; retry when Pack build completes', vim.log.levels.WARN)
      return
    end

    -- adapter 通信端口与被调试目标端口必须分离，例如 pwa-chrome 的 config.port 是 Chrome 端口
    local port = '${port}'
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
end

return M
