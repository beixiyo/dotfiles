if not vim.g.neovide then return end

local function save()
  vim.cmd.write()
end

local function copy()
  vim.cmd([[normal! "+y]])
end

local function paste()
  vim.api.nvim_paste(vim.fn.getreg('+'), true, -1)
end

local function scroll(key)
  return function()
    local lines = vim.v.count > 0 and vim.v.count or 5
    vim.cmd(('normal! %d%s'):format(lines, key))
  end
end

local function clamp(value, min, max)
  return math.max(min, math.min(max, value))
end

local function change_scale(delta)
  return function()
    local next_scale = (vim.g.neovide_scale_factor or 1) + delta
    vim.g.neovide_scale_factor = clamp(next_scale, 0.7, 2)
  end
end

local function reset_scale()
  vim.g.neovide_scale_factor = 1
end

vim.o.guifont = 'Maple Mono NF:h12'
vim.g.neovide_scale_factor = vim.g.neovide_scale_factor or 1
vim.g.neovide_confirm_quit = true
vim.g.neovide_remember_window_size = true

-- macOS Option 默认会输入特殊字符；Neovide 需要显式把 Option 当作 Meta/Alt，
-- 否则 <C-A-*> / <A-*> 这类快捷键进不到 Neovim
vim.g.neovide_input_macos_option_key_is_meta = 'both'
-- macOS Option+h 是 dead key。Neovide 的 IME 路径可能先吃掉它，导致 <C-A-h> 不触发
-- 只在输入文字和搜索时打开 IME，普通/可视/终端操作保持快捷键优先
vim.g.neovide_input_ime = false

vim.opt.title = true
vim.opt.titlestring = 'nvim · %t%( %M%)'

vim.keymap.set({ 'n', 'i', 'v' }, '<D-s>', save, { desc = 'Save' })
vim.keymap.set('v', '<D-c>', copy, { silent = true, desc = 'Copy' })
vim.keymap.set({ 'n', 'i', 'v', 'c', 't' }, '<D-v>', paste, { silent = true, desc = 'Paste' })
-- 终端里常用 Ctrl+Shift+V 粘贴；Neovide 在不同 Karabiner / GUI 路径下可能收到 C-S-v 或 D-S-v
vim.keymap.set({ 'n', 'i', 'v', 'c', 't' }, '<C-S-v>', paste, { silent = true, desc = 'Paste' })
vim.keymap.set({ 'n', 'i', 'v', 'c', 't' }, '<D-S-v>', paste, { silent = true, desc = 'Paste' })
vim.keymap.set({ 'n', 'i', 'v', 'c', 't' }, '<D-V>', paste, { silent = true, desc = 'Paste' })
vim.keymap.set({ 'n', 'i', 'v', 'c', 't' }, '<C-=>', change_scale(0.1), { silent = true, desc = 'Zoom in' })
vim.keymap.set({ 'n', 'i', 'v', 'c', 't' }, '<C-+>', change_scale(0.1), { silent = true, desc = 'Zoom in' })
vim.keymap.set({ 'n', 'i', 'v', 'c', 't' }, '<C-->', change_scale(-0.1), { silent = true, desc = 'Zoom out' })
vim.keymap.set({ 'n', 'i', 'v', 'c', 't' }, '<C-0>', reset_scale, { silent = true, desc = 'Reset zoom' })

-- Karabiner 或 GUI 层可能把物理 Ctrl 变成 Command
-- C-e / C-y 仍交给后续 vv-utils.scroll 接管；这里补 D-e / D-y 兜住 Neovide 实际收到的按键
vim.keymap.set({ 'n', 'x' }, '<D-e>', scroll(string.char(5)), { silent = true, desc = 'Scroll down' })
vim.keymap.set({ 'n', 'x' }, '<D-y>', scroll(string.char(25)), { silent = true, desc = 'Scroll up' })

local function set_ime(args)
  vim.g.neovide_input_ime = args.event:match('Enter$') ~= nil
end

local ime_group = vim.api.nvim_create_augroup('config_neovide_ime', { clear = true })

vim.api.nvim_create_autocmd({ 'InsertEnter', 'InsertLeave' }, {
  group = ime_group,
  callback = set_ime,
})

vim.api.nvim_create_autocmd({ 'CmdlineEnter', 'CmdlineLeave' }, {
  group = ime_group,
  pattern = { '/', '\\?' },
  callback = set_ime,
})
