-- smart-splits.nvim：直觉式窗口焦点切换与大小调整
-- Ctrl+Alt+h/j/k/l 切换焦点，Ctrl+Alt+方向键调整大小
local SCROLLBAR_FT = 'vv-scrollbar'

local function resize(name)
  return function()
    local win = vim.api.nvim_get_current_win()
    local state = require('vv-scrollbar.core.state')
    local view = require('vv-scrollbar.core.view')
    local widths = {}

    -- map view 是源窗口右侧的真实 split。若直接调整，smart-splits 改到的是
    -- 源窗口与 map view 之间的边界，随后滚动条恢复宽度，看起来只会抖一下
    for parent, bar in pairs(state.bars) do
      if vim.api.nvim_win_is_valid(parent) and vim.api.nvim_win_is_valid(bar.win) then
        widths[#widths + 1] = {
          win = parent,
          width = vim.api.nvim_win_get_width(parent)
            + vim.api.nvim_win_get_width(bar.win)
            + 1,
        }
      end
    end

    view.close_all()
    for _, item in ipairs(widths) do
      if vim.api.nvim_win_is_valid(item.win) then
        vim.api.nvim_win_set_width(item.win, item.width)
      end
    end
    vim.api.nvim_set_current_win(win)

    local ok, err = xpcall(function()
      require('smart-splits')[name]()
    end, debug.traceback)
    view.refresh()

    if not ok then error(err) end
  end
end

---@return boolean
local function on_scrollbar()
  return vim.bo.filetype == SCROLLBAR_FT
end

-- vv-scrollbar 用真实 split 创建（非浮窗），是布局树里的正经窗口，wincmd 会停在它上面
-- split 无法像浮窗那样设 focusable = false，smart-splits 的 ignored_filetypes 也只作用于
-- resize 和 at_edge = 'split'，管不到 move_cursor，所以只能在移动后自己跨过去
local function move(name)
  return function()
    local jump = require('smart-splits')[name]
    local origin = vim.api.nvim_get_current_win()

    jump()
    if not on_scrollbar() then return end

    -- 落在滚动条上：朝同方向再跳一次，跨到它后面的真实窗口
    jump()
    if not on_scrollbar() then return end

    -- 仍在滚动条上，说明它就是这个方向的最后一个窗口（at_edge = 'stop' 卡住），退回原窗口
    if vim.api.nvim_win_is_valid(origin) then
      vim.api.nvim_set_current_win(origin)
    end
  end
end

local function keymaps()
  local keys = {
    { '<C-A-h>', move('move_cursor_left'),  mode = { 'n', 't' }, desc = 'Focus left' },
    { '<C-A-j>', move('move_cursor_down'),  mode = { 'n', 't' }, desc = 'Focus down' },
    { '<C-A-k>', move('move_cursor_up'),    mode = { 'n', 't' }, desc = 'Focus up' },
    { '<C-A-l>', move('move_cursor_right'), mode = { 'n', 't' }, desc = 'Focus right' },
    { '<C-A-Left>',  resize('resize_left'),  desc = 'Resize left' },
    { '<C-A-Right>', resize('resize_right'), desc = 'Resize right' },
    { '<C-A-Up>',    resize('resize_up'),    desc = 'Resize up' },
    { '<C-A-Down>',  resize('resize_down'),  desc = 'Resize down' },
  }

  if vim.g.neovide then
    -- Neovide 在 macOS + Karabiner 下可能收到 Command+Alt，而不是 Ctrl+Alt；
    -- h 方向由 Karabiner 转成 F19，绕过 macOS Option+h 死键
    -- 这组只在 GUI 中补齐，不影响终端 / tmux 的原有按键通道
    vim.list_extend(keys, {
      { '<D-A-h>', move('move_cursor_left'),  mode = { 'n', 't' }, desc = 'Focus left' },
      { '<F19>', move('move_cursor_left'), mode = { 'n', 't' }, desc = 'Focus left' },
      { '<D-A-j>', move('move_cursor_down'),  mode = { 'n', 't' }, desc = 'Focus down' },
      { '<D-A-k>', move('move_cursor_up'),    mode = { 'n', 't' }, desc = 'Focus up' },
      { '<D-A-l>', move('move_cursor_right'), mode = { 'n', 't' }, desc = 'Focus right' },
      { '<D-A-Left>',  resize('resize_left'),  desc = 'Resize left' },
      { '<D-A-Right>', resize('resize_right'), desc = 'Resize right' },
      { '<D-A-Up>',    resize('resize_up'),    desc = 'Resize up' },
      { '<D-A-Down>',  resize('resize_down'),  desc = 'Resize down' },
    })
  end

  return keys
end

---@type PackSpec
return {
  desc = '智能窗口焦点切换与大小调整',
  url = 'https://github.com/mrjones2014/smart-splits.nvim',
  main = 'smart-splits',

  -- Kitty backend 硬编码调用 `kitten neighboring_window.py` / `relative_resize.py`，
  -- 必须把仓库自带的 Python kitten 脚本拷到 ~/.config/kitty/，否则 Nvim → Kitty 跨界无效
  build = './kitty/install-kittens.bash',

  keys = keymaps,

  ---@return SmartSplitsConfig
  opts = function()
    ---@type SmartSplitsConfig
    local opts = {
      default_amount = 3,
      -- Kitty backend 不支持 wrap（插件会硬降级为 stop 并打告警），统一用 stop
      at_edge = 'stop',
    }

    if vim.g.neovide then
      -- Neovide 只需要管理 Neovim 自身 split，不需要探测 kitty/tmux/wezterm
      opts.multiplexer_integration = false
    end

    return opts
  end,

  ---@param spec PackSpec
  ---@param opts SmartSplitsConfig
  config = function(spec, opts)
    require('smart-splits').setup(opts)

    -- 修复：插件自带 on_exit 用 vim.fn.jobstart(detach=true) 异步清理 @pane-is-vim，
    -- 在 VimLeavePre 期间可能来不及执行，导致退出 nvim 后 tmux 仍将按键 send-keys 到 shell
    -- 这里用 vim.system():wait() 同步清理，确保退出前一定完成
    if vim.env.TMUX then
      vim.api.nvim_create_autocmd('VimLeavePre', {
        callback = function()
          local pane = vim.env.TMUX_PANE
          if not pane then return end
          local socket = vim.split(vim.env.TMUX, ',', { trimempty = true })[1]
          if not socket then return end
          vim.system({ 'tmux', '-S', socket, 'set-option', '-pt', pane, '@pane-is-vim', '0' }):wait()
        end,
      })
    end
  end,
}
