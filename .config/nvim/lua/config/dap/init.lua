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

  local dap = require('dap')
  if next(dap.sessions()) then
    dap.continue()
    return
  end

  local configurations = {}
  local providers = vim.tbl_keys(dap.providers.configs)
  table.sort(providers)

  for _, provider in ipairs(providers) do
    local items = dap.providers.configs[provider](vim.api.nvim_get_current_buf())
    if vim.islist(items) then vim.list_extend(configurations, items) end
  end

  if #configurations == 0 then
    vim.notify('No DAP configuration found for ' .. vim.bo.filetype, vim.log.levels.INFO)
    return
  end

  if #configurations == 1 then
    dap.run(configurations[1])
    return
  end

  vim.ui.select(configurations, {
    prompt = 'Configuration',
    kind = 'dap-configuration',
    format_item = function(config) return config.name end,
  }, function(config)
    if config then
      dap.run(config)
    else
      vim.notify('No configuration selected', vim.log.levels.INFO)
    end
  end)
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
