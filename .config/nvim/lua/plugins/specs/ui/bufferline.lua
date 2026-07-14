-- 顶部 Buffer 标签页
---@type PackSpec
return {
  desc = '标签式 Buffer 栏',
  url = 'https://github.com/akinsho/bufferline.nvim',
  main = 'bufferline',
  dependencies = {
    'https://github.com/nvim-tree/nvim-web-devicons',
    'beixiyo/vv-utils.nvim',  -- bufdel
    'beixiyo/vv-icons.nvim',
  },

  -- UIEnter：dashboard 期间禁用 statusline，UIEnter 后再加载无视觉差
  event = { 'UIEnter' },

  config = function()
    local bufdel = require('vv-utils.bufdelete')
    local icon = require('vv-icons').buffers .. ' '

    -- 点击 buffer 标签时切到目标 buffer
    -- 默认是 `"buffer %d"`，在「当前窗口」执行。但若焦点停在 winfixbuf 的侧栏树窗
    -- （vv-explorer / vv-git 等），:buffer 会被锁定窗口拒绝 → E1513
    -- 故先找一个可切换的普通窗口跳过去，再切 buffer；找不到则在侧栏旁开个分屏兜底
    local function open_in_editable_win(bufnr)
      local cur = vim.api.nvim_get_current_win()
      if not vim.wo[cur].winfixbuf then
        vim.cmd('buffer ' .. bufnr)
        return
      end

      local target
      for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local b = vim.api.nvim_win_get_buf(w)
        local floating = vim.api.nvim_win_get_config(w).relative ~= ''
        if not floating and not vim.wo[w].winfixbuf and vim.bo[b].buftype == '' then
          target = w
          break
        end
      end

      if target then
        vim.api.nvim_set_current_win(target)
        vim.cmd('buffer ' .. bufnr)
      else
        -- 整屏只剩侧栏：在右侧开普通分屏承载
        vim.cmd('botright vsplit | buffer ' .. bufnr)
      end
    end

    -- 底色跟随当前 tokyonight style，避免切主题后与整体背景脱节
    local p = require('tools').palette.get()

    -- bar 三层底色梯度（moon 全紫调；bufferline 默认会把 normal_bg 压暗成近黑，这里全部拉回）
    --   fill 最深 → 非活动 buffer 居中 → 选中 tab 用强调色
    local fill_bg     = p.bg_dark   -- 整条 bar 空白填充，比编辑器略深做分隔
    local inactive_bg = p.bg        -- 非活动 buffer，与编辑器同底
    local active_bg   = p.blue7     -- 选中 tab 强调；想含蓄换 p.bg_highlight，想更亮换 p.blue0

    local active = { bg = active_bg }

    -- 非活动段：只覆盖 bg 拉回 inactive_bg，fg 走 bufferline 默认
    -- （config:merge 用 vim.tbl_deep_extend，逐键合并，不会丢默认 fg）
    local highlights = { fill = { bg = fill_bg } }

    for _, g in ipairs({
      'background',   'buffer_visible',
      'modified',     'modified_visible',
      'duplicate',    'duplicate_visible',
      'close_button', 'close_button_visible',
      'numbers',      'numbers_visible',
      'separator',    'separator_visible',
      'diagnostic',   'diagnostic_visible',
      'hint',    'hint_visible',    'hint_diagnostic',    'hint_diagnostic_visible',
      'info',    'info_visible',    'info_diagnostic',    'info_diagnostic_visible',
      'warning', 'warning_visible', 'warning_diagnostic', 'warning_diagnostic_visible',
      'error',   'error_visible',   'error_diagnostic',   'error_diagnostic_visible',
      'pick',    'pick_visible',
      'tab',     'tab_close',
    }) do
      highlights[g] = { bg = inactive_bg }
    end

    -- 选中段：统一强调底色
    for _, g in ipairs({
      'modified_selected', 'diagnostic_selected',
      'hint_selected',     'hint_diagnostic_selected',
      'info_selected',     'info_diagnostic_selected',
      'warning_selected',  'warning_diagnostic_selected',
      'error_selected',    'error_diagnostic_selected',
      'numbers_selected',  'close_button_selected',
      'separator_selected','indicator_selected', 'pick_selected',
      'tab_selected',      'tab_separator_selected',
    }) do
      highlights[g] = active
    end

    highlights.buffer_selected    = { bg = active_bg, fg = '#ffffff', bold = true, italic = false }
    highlights.duplicate_selected = vim.tbl_extend('force', active, { italic = true })

    ---@type bufferline.UserConfig
    require('bufferline').setup({
      options = {
        themable = false,
        close_command = function(n) bufdel(n) end,
        left_mouse_command = open_in_editable_win,
        right_mouse_command = function(n) bufdel(n) end,
        diagnostics = 'nvim_lsp',
        always_show_bufferline = true,
        indicator = { style = 'none' },
        tab_size = 0,
        separator_style = { '', '' },
        hover = { enabled = true, delay = 200, reveal = { 'close' } },
      },
      highlights = highlights,
    })

    vim.api.nvim_create_autocmd({ 'BufAdd', 'BufDelete' }, {
      callback = function()
        if _G.nvim_bufferline then
          vim.schedule(function() pcall(_G.nvim_bufferline) end)
        end
      end,
    })

    local map = vim.keymap.set
    -- buffer 切换沿用 Neovim 0.11+ 内置的 [b / ]b / [B / ]B
    map('n', '<leader>bd', bufdel.smart, { desc = icon .. 'Close buffer', silent = true })
    map('n', '<leader>bD', function() bufdel({ force = true }) end, { desc = icon .. 'Force close buffer', silent = true })
    map('n', '<leader>bh', '<cmd>BufferLineCloseLeft<cr>', { desc = icon .. 'Close buffers left', silent = true })
    map('n', '<leader>bl', '<cmd>BufferLineCloseRight<cr>', { desc = icon .. 'Close buffers right', silent = true })
    map('n', '<leader>bo', function() bufdel.other() end, { desc = icon .. 'Close other buffers', silent = true })
    map('n', '<leader>ba', function()
      -- 显式 3 步编排：关 vv-explorer → 删全部 listed bufs → 打开 dashboard
      pcall(function() require('vv-explorer').close() end)
      bufdel.all()
      vim.schedule(function()
        pcall(function() require('vv-dashboard').open() end)
      end)
    end, { desc = icon .. 'Close all buffers', silent = true })
  end,
}
