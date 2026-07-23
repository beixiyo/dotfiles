-- 自绘滚动条（Braille 代码地图 / 完整背景轨道 / 点击跳转 / 拖拽 / 状态标记）
---@type PackSpec
return {
  desc = '滚动条',
  url = 'beixiyo/vv-scrollbar.nvim',
  main = 'vv-scrollbar',
  dependencies = { 'beixiyo/vv-utils.nvim' },
  cmd = {
    'VVScrollbarEnable',
    'VVScrollbarDisable',
    'VVScrollbarToggle',
    'VVScrollbarToggleView',
    'VVScrollbarRefresh',
  },
  event = { 'BufReadPost', 'BufNewFile', 'User VVGitStatusChanged' },

  ---@type VVScrollbarConfig
  -- opts = function()
  --   local p = require('tools.palette').get()
  --
  --   return {
  --     highlights = {
  --       track = { bg = p.bg },
  --       separator = { fg = p.bg, bg = p.bg },
  --       map_view = { fg = p.comment },
  --       map_cursor = { fg = p.blue },
  --       thumb = { bg = p.bg_highlight },
  --       active = { bg = p.fg_gutter },
  --       cursor = { fg = p.blue },
  --       search = { fg = p.orange },
  --       mark = { fg = p.purple },
  --       quickfix = { fg = p.yellow },
  --       diag_error = { fg = p.red },
  --       diag_warn = { fg = p.yellow },
  --       diag_info = { fg = p.blue },
  --       diag_hint = { fg = p.cyan },
  --     },
  --   }
  -- end,
}
