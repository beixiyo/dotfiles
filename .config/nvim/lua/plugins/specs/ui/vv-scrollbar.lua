-- 自绘滚动条（完整背景轨道 / 点击跳转 / 拖拽 / 诊断与 git 标记）
---@type PackSpec
return {
  desc = '滚动条',
  url = 'beixiyo/vv-scrollbar.nvim',
  main = 'vv-scrollbar',
  dependencies = { 'beixiyo/vv-utils.nvim' },
  cmd = { 'VVScrollbarEnable', 'VVScrollbarDisable', 'VVScrollbarToggle', 'VVScrollbarRefresh' },
  event = { 'BufReadPost', 'BufNewFile', 'User VVGitStatusChanged' },

  ---@type VVScrollbarConfig
  opts = function()
    local p = require('tools.palette').get()

    return {
      width = 2,
      right_offset = 0,
      min_thumb = 2,
      search_line_limit = 20000,
      highlights = {
        track = { bg = p.bg_highlight },
        thumb = { bg = p.fg_gutter },
        hover = { bg = p.border },
        cursor = { fg = p.blue },
        search = { fg = p.orange },
        mark = { fg = p.purple },
        quickfix = { fg = p.yellow },
        diag_error = { fg = p.red },
        diag_warn = { fg = p.yellow },
        diag_info = { fg = p.blue },
        diag_hint = { fg = p.cyan },
      },
    }
  end,
}
