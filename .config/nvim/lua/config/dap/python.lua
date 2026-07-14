-- Python debugpy 配置
local M = {}

function M.setup()
  -- 使用专用 debugpy 环境，避免依赖或污染当前项目的 Python 环境
  local debugpy = vim.fn.stdpath('data') .. '/debugpy/bin/python'
  if vim.fn.executable(debugpy) == 1 then
    require('dap-python').setup(debugpy)
  else
    vim.notify('debugpy is not installed', vim.log.levels.WARN)
  end
end

return M
