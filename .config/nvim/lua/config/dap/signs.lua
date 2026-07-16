-- DAP 断点与停止位置标记，不依赖调试面板
local M = {}

function M.setup()
  local icons = require('vv-icons')

  vim.fn.sign_define('DapBreakpoint', {
    text = icons.debug,
    texthl = 'DiagnosticError',
    linehl = '',
    numhl = '',
  })
  vim.fn.sign_define('DapBreakpointCondition', {
    text = icons.debug,
    texthl = 'DiagnosticWarn',
    linehl = '',
    numhl = '',
  })
  vim.fn.sign_define('DapBreakpointRejected', {
    text = icons.debug,
    texthl = 'DiagnosticWarn',
    linehl = '',
    numhl = '',
  })
  vim.fn.sign_define('DapLogPoint', {
    text = icons.debug,
    texthl = 'DiagnosticInfo',
    linehl = '',
    numhl = '',
  })
  vim.fn.sign_define('DapStopped', {
    text = icons.arrow_right,
    texthl = 'DiagnosticInfo',
    linehl = 'Visual',
    numhl = '',
  })
end

return M
