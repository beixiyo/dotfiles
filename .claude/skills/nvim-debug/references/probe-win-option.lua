-- 探针：新窗口如何获得 win-local 选项（以 scrollbind 为例）。nvim 升级后重跑，核对 case-win-option-inherit.md 的规则表
-- 用法：nvim --headless -u NONE -l probe-win-option.lua
-- 验证环境：nvim 0.13.0-dev-1617（2026-10-17）；预期输出见文件末尾注释

local OPT = 'scrollbind'

local function reset()
  vim.cmd('tabnew')
  vim.cmd('set no' .. OPT .. ' | setlocal no' .. OPT)
end

local function float(buf, extra)
  local cfg = vim.tbl_extend('force', { relative = 'editor', row = 1, col = 1, width = 5, height = 2 }, extra or {})
  return vim.api.nvim_open_win(buf, false, cfg)
end

local function newbuf() return vim.api.nvim_create_buf(false, true) end

local function copy_of(win)
  return vim.api.nvim_get_option_value(OPT, { scope = 'global', win = win })
end

local rows = {}
local function row(label, value) rows[#rows + 1] = ('%-62s %s'):format(label, tostring(value)) end


-- 1. 当前窗口 setlocal，再开窗
reset()
vim.cmd('setlocal ' .. OPT)
row('setlocal(cur)      -> 新 buffer 浮窗', vim.wo[float(newbuf())][OPT])
row('setlocal(cur)      -> 同 buffer 浮窗', vim.wo[float(vim.api.nvim_get_current_buf())][OPT])
row('setlocal(cur)      -> style=minimal 同 buffer 浮窗', vim.wo[float(vim.api.nvim_get_current_buf(), { style = 'minimal' })][OPT])
vim.cmd('split')
row('setlocal(cur)      -> :split（同 buffer）', vim.wo[OPT])

-- 2. 当前窗口 :set / vim.wo（不带 scope）
reset()
vim.cmd('set ' .. OPT)
row(':set(cur)          -> 新 buffer 浮窗', vim.wo[float(newbuf())][OPT])

reset()
vim.wo[OPT] = true
row('vim.wo.x=v(cur)    -> 新 buffer 浮窗', vim.wo[float(newbuf())][OPT])

-- 3. 当前窗口 scope=local / [0]
reset()
vim.api.nvim_set_option_value(OPT, true, { scope = 'local', win = 0 })
row("scope='local'(cur) -> 新 buffer 浮窗", vim.wo[float(newbuf())][OPT])

reset()
vim.wo[0][0][OPT] = true
row('vim.wo[0][0].x(cur)-> 新 buffer 浮窗', vim.wo[float(newbuf())][OPT])

-- 4. 非当前窗口 W
reset()
local base = vim.api.nvim_get_current_win()
vim.cmd('vsplit')
local W = vim.api.nvim_get_current_win()
vim.api.nvim_set_current_win(base)

vim.api.nvim_set_option_value(OPT, true, { win = W })
row('不带 scope 设 W    -> W 局部值', vim.wo[W][OPT])
row('不带 scope 设 W    -> W 的全局副本', copy_of(W))
row('不带 scope 设 W    -> base 的全局副本', copy_of(base))
row('不带 scope 设 W    -> cur=base 开新 buffer 浮窗', vim.wo[float(newbuf())][OPT])
row('不带 scope 设 W    -> cur=base, relative=win win=W', vim.wo[float(newbuf(), { relative = 'win', win = W })][OPT])
vim.api.nvim_set_current_win(W)
row('不带 scope 设 W    -> cur=W 开新 buffer 浮窗', vim.wo[float(newbuf())][OPT])
vim.api.nvim_set_current_win(base)

vim.api.nvim_set_option_value(OPT, false, { win = W })
vim.api.nvim_set_option_value(OPT, true, { scope = 'local', win = W })
row("scope='local' 设 W -> W 局部值", vim.wo[W][OPT])
row("scope='local' 设 W -> W 的全局副本", copy_of(W))

print(table.concat(rows, '\n'))

--[[ 预期输出（0.13.0-dev-1617）：
setlocal(cur)      -> 新 buffer 浮窗                                  false
setlocal(cur)      -> 同 buffer 浮窗                                  true
setlocal(cur)      -> style=minimal 同 buffer 浮窗                    true
setlocal(cur)      -> :split（同 buffer）                             true
:set(cur)          -> 新 buffer 浮窗                                  true
vim.wo.x=v(cur)    -> 新 buffer 浮窗                                  true
scope='local'(cur) -> 新 buffer 浮窗                                  false
vim.wo[0][0].x(cur)-> 新 buffer 浮窗                                  false
不带 scope 设 W    -> W 局部值                                        true
不带 scope 设 W    -> W 的全局副本                                    true
不带 scope 设 W    -> base 的全局副本                                 false
不带 scope 设 W    -> cur=base 开新 buffer 浮窗                       false
不带 scope 设 W    -> cur=base, relative=win win=W                    false
不带 scope 设 W    -> cur=W 开新 buffer 浮窗                          true
scope='local' 设 W -> W 局部值                                        true
scope='local' 设 W -> W 的全局副本                                    false
]]
