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

  ---@type VVScrollbarOpts
  opts = {
    -- 仅降级滚动条；保留正文 Markdown 渲染。可按实际文件调整门槛
    -- markdown 高亮 query 带 conceal_lines，conceallevel > 0 时全文 nvim_win_text_height
    -- 会对每行触发 treesitter 的 _on_conceal_line → parse（含注入），240 行约 40ms/次，
    -- 每次滚动算两次，C-e / C-y 每步卡 80ms 左右
    lightweight = function(ctx)
      if ctx.filetype ~= 'markdown' then return false end
      return ctx.line_count >= 1000 or vim.wo[ctx.win].conceallevel > 0
    end,
    map_view = {
      enabled = false
    }
  },

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
