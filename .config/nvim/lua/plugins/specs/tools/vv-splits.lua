-- vv-splits：基于原生分隔线 API 的 Neovim / multiplexer 无缝导航与缩放

local function action(name, direction)
  return function()
    require('vv-splits')[name]({ direction = direction })
  end
end

local function is_scrollbar(win)
  local buf = vim.api.nvim_win_get_buf(win)
  return vim.api.nvim_get_option_value('filetype', { buf = buf }) == 'vv-scrollbar'
end

local function with_resize(action)
  local ok, scrollbar = pcall(require, 'vv-scrollbar')
  if not ok or type(scrollbar.with_layout_suspended) ~= 'function' then
    return action()
  end
  return scrollbar.with_layout_suspended(action)
end

local function keymaps()
  local keys = {
    { '<C-A-h>', action('move', 'left'), mode = { 'n', 't' }, desc = 'Focus left' },
    { '<C-A-j>', action('move', 'down'), mode = { 'n', 't' }, desc = 'Focus down' },
    { '<C-A-k>', action('move', 'up'), mode = { 'n', 't' }, desc = 'Focus up' },
    { '<C-A-l>', action('move', 'right'), mode = { 'n', 't' }, desc = 'Focus right' },
    { '<C-A-Left>', action('resize', 'left'), mode = { 'n', 't' }, desc = 'Resize left' },
    { '<C-A-Right>', action('resize', 'right'), mode = { 'n', 't' }, desc = 'Resize right' },
    { '<C-A-Up>', action('resize', 'up'), mode = { 'n', 't' }, desc = 'Resize up' },
    { '<C-A-Down>', action('resize', 'down'), mode = { 'n', 't' }, desc = 'Resize down' },
  }

  if vim.g.neovide then
    -- macOS Option+h 是 dead key；Karabiner 用 F19 补齐 h，其他方向兼容 Command+Alt
    vim.list_extend(keys, {
      { '<D-A-h>', action('move', 'left'), mode = { 'n', 't' }, desc = 'Focus left' },
      { '<F19>', action('move', 'left'), mode = { 'n', 't' }, desc = 'Focus left' },
      { '<D-A-j>', action('move', 'down'), mode = { 'n', 't' }, desc = 'Focus down' },
      { '<D-A-k>', action('move', 'up'), mode = { 'n', 't' }, desc = 'Focus up' },
      { '<D-A-l>', action('move', 'right'), mode = { 'n', 't' }, desc = 'Focus right' },
      { '<D-A-Left>', action('resize', 'left'), mode = { 'n', 't' }, desc = 'Resize left' },
      { '<D-A-Right>', action('resize', 'right'), mode = { 'n', 't' }, desc = 'Resize right' },
      { '<D-A-Up>', action('resize', 'up'), mode = { 'n', 't' }, desc = 'Resize up' },
      { '<D-A-Down>', action('resize', 'down'), mode = { 'n', 't' }, desc = 'Resize down' },
    })
  end

  return keys
end

---@type PackSpec
return {
  desc = 'Neovim 与 multiplexer 无缝窗口导航和缩放',
  url = 'beixiyo/vv-splits.nvim',
  main = 'vv-splits',

  -- Kitty native 模式需要在第一个按键前设置 IS_NVIM，不能只靠 keys 懒加载
  event = 'VimEnter',
  keys = keymaps,

  ---@return VVSplitsSetupOpts
  opts = function()
    return {
      amount = 3,
      mux = vim.g.neovide and false or 'auto',
      float_behavior = 'previous',
      skip_window = is_scrollbar,
      with_resize = with_resize,
    }
  end,
}
