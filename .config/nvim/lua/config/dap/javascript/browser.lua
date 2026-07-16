-- 浏览器调试配置
local browser_url = require('config.dap.url')

local M = {}

---@param skip_files string[]
---@return table[]
function M.configurations(skip_files)
  return {
    {
      type = 'pwa-chrome',
      request = 'launch',
      name = 'Launch browser',
      url = browser_url.prompt,
      webRoot = '${workspaceFolder}',
      sourceMaps = true,
      skipFiles = skip_files,
    },
  }
end

return M
