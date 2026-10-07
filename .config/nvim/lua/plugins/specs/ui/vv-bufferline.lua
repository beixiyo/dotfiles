-- 分屏独立 Buffer 栏：使用 window-local winbar 模拟 VSCode split tabs
local function open_dashboard_if_tab_empty_later(tabpage)
  vim.schedule(function()
    -- 延迟期间用户可能切 tab；不在新 tab 打开 dashboard，也不强抢焦点
    if not vim.api.nvim_tabpage_is_valid(tabpage) or vim.api.nvim_get_current_tabpage() ~= tabpage then return end
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
      if vim.api.nvim_win_is_valid(win) then
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted and vim.bo[buf].buftype == '' then return end
      end
    end

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
    -- 展示策略：关闭后 tab 空时回到 dashboard；全部关闭时顺手收起 vv-explorer
    opts.hooks = {
      after_close = function(ctx)
        if not ctx.completed then return end
        if ctx.action == 'close_all' then close_explorer() end
        open_dashboard_if_tab_empty_later(ctx.tabpage)
      end,
    }
    bufferline.setup(opts)
  end,
}
