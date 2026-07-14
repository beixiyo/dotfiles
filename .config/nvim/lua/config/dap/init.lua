-- 统一编排 nvim-dap、调试面板与各语言 adapter
local go = require('config.dap.go')

local M = {}

local did_setup = false

function M.continue()
  local err = vim.bo.filetype == 'go' and go.debug_error() or nil
  if err then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  require('dap').continue()
end

function M.setup()
  if did_setup then return end

  -- 让依赖 DAP 的大型 adapter 跟随调试工作流懒加载
  vim.api.nvim_exec_autocmds('User', { pattern = 'DapSetup' })

  local dap = require('dap')

  require('config.dap.ui').setup(dap)
  require('config.dap.javascript').setup(dap)
  require('config.dap.python').setup()
  go.setup(dap)
  require('config.dap.rust').setup(dap)

  -- 仅在全部模块初始化成功后锁定，失败时允许下次调用重试
  did_setup = true
end

return M
