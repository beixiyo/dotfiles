-- 诊断外观：左侧 sign icon、行尾 virtual_text、悬浮窗

local M = {}

function M.setup()
  local icons = require('vv-icons')
  local diag_icons = {
    Error = icons.diagnostics_error,
    Warn  = icons.diagnostics_warn,
    Hint  = icons.diagnostics_hint,
    Info  = icons.diagnostics_info,
  }

  local s = vim.diagnostic.severity
  vim.diagnostic.config({
    virtual_text = {
      spacing = 2,
      source = 'if_many',
      prefix = function(diagnostic)
        if diagnostic.severity == s.ERROR then return diag_icons.Error
        elseif diagnostic.severity == s.WARN then return diag_icons.Warn
        elseif diagnostic.severity == s.HINT then return diag_icons.Hint
        else return diag_icons.Info end
      end,
    },
    signs = {
      text = {
        [s.ERROR] = diag_icons.Error,
        [s.WARN]  = diag_icons.Warn,
        [s.HINT]  = diag_icons.Hint,
        [s.INFO]  = diag_icons.Info,
      },
    },
    underline = true,
    update_in_insert = false,
    severity_sort = true,
    float = { border = 'rounded', source = 'if_many' },
  })
end

return M
