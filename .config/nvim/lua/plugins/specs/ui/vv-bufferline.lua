-- 分屏独立 Buffer 栏：使用 window-local winbar 模拟 VSCode split tabs
local function open_dashboard_later()
  vim.schedule(function()
    pcall(function() require('vv-dashboard').open() end)
  end)
end

local function close_explorer()
  pcall(function() require('vv-explorer').close() end)
end

-- Neovide bug，如果使用 winbar 会导致窗口滚动动画消失
-- https://github.com/neovide/neovide/issues/2406
-- https://github.com/neovide/neovide/pull/2165
-- https://github.com/neovide/neovide/pull/2438
-- https://github.com/neovide/neovide/issues/3128
local function default_render_target()
  if vim.g.vv_bufferline_render_target then return vim.g.vv_bufferline_render_target end

  -- Neovide 对非空 window-local winbar 的滚动动画不稳定；保留 bufferline，
  -- 但默认挂到全局 tabline。终端仍使用每窗口 winbar，维持 split 独立标签
  if vim.g.neovide then return 'tabline' end

  return 'winbar'
end

---@type PackSpec
return {
  desc = '分屏独立 Buffer 栏',
  url = 'beixiyo/vv-bufferline.nvim',
  main = 'vv-bufferline',
  dependencies = {
    'beixiyo/vv-utils.nvim',
    'beixiyo/vv-icons.nvim',
    'https://github.com/nvim-tree/nvim-web-devicons',
  },

  event = { 'UIEnter' },

  opts = function()
    local p = require('tools.palette').get()

    return {
      colors = {
        fill_bg = p.bg_dark,
        inactive_bg = p.bg,
        active_bg = p.blue7,
        inactive_fg = p.fg_dark,
        active_fg = '#ffffff',
        muted_fg = p.comment,
        modified_fg = p.yellow,
      },
      render_target = default_render_target(),
    }
  end,

  config = function(_, opts)
    local bufferline = require('vv-bufferline')
    local icon = require('vv-icons').buffers .. ' '
    bufferline.setup(opts)

    local map = vim.keymap.set

    -- 按当前 split 的可见标签顺序切换，避免内置 :bnext 遍历全局 listed buffer
    map('n', '[b', function() bufferline.cycle(-vim.v.count1) end, { desc = icon .. 'Previous buffer', silent = true })
    map('n', ']b', function() bufferline.cycle(vim.v.count1) end, { desc = icon .. 'Next buffer', silent = true })
    map('n', '<leader>bd', bufferline.close_current, { desc = icon .. 'Close buffer', silent = true })
    map('n', '<leader>bD', function() bufferline.close_current({ force = true }) end, { desc = icon .. 'Force close buffer', silent = true })
    map('n', '<leader>bh', '<cmd>VVBufferlineCloseLeft<cr>', { desc = icon .. 'Close buffers left', silent = true })
    map('n', '<leader>bl', '<cmd>VVBufferlineCloseRight<cr>', { desc = icon .. 'Close buffers right', silent = true })
    map('n', '<leader>bo', bufferline.close_others, { desc = icon .. 'Close other buffers', silent = true })
    map('n', '<leader>ba', function()
      -- 显式 3 步编排：关 vv-explorer → 清理所有分组缓冲区并收起分屏 → 打开 dashboard
      close_explorer()
      bufferline.close_all({ close_windows = true })
      open_dashboard_later()
    end, { desc = icon .. 'Close all buffers', silent = true })
  end,
}
