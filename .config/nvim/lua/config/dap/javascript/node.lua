-- Node.js 与 Bun 调试配置
local M = {}

---@param skip_files string[]
---@return table[]
function M.configurations(skip_files)
  return {
    {
      type = 'pwa-node',
      request = 'launch',
      name = 'Launch current file',
      program = '${file}',
      cwd = '${workspaceFolder}',
      sourceMaps = true,
      skipFiles = skip_files,
      console = 'integratedTerminal',
    },
    {
      type = 'pwa-node',
      request = 'attach',
      name = 'Attach to process',
      processId = require('dap.utils').pick_process,
      cwd = '${workspaceFolder}',
      sourceMaps = true,
      skipFiles = skip_files,
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
      skipFiles = skip_files,
      console = 'integratedTerminal',
    },
  }
end

return M
