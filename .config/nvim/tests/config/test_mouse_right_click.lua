-- 驱动真实鼠标输入验证跨窗口右键分发；逐 case child 隔离 cwd、持久目录及模块状态
-- popup 打开时只调用 fast API，先关闭菜单再查询 Lua 状态，避免同步 RPC 阻塞
local H = dofile('tests/helpers.lua')
local T, child = H.new_set({ 'VV_ICONS' })

local function lua(code, ...)
  return child.api.nvim_exec_lua(code, { ... })
end

-- row / col 相对窗口文本区，跳过行号等 textoff
local function right_click(win, row, col)
  local pos = child.api.nvim_win_get_position(win)
  col = col + lua('return vim.fn.getwininfo(...)[1].textoff', win)
  child.api.nvim_input_mouse('right', 'press', '', 0, pos[1] + row, pos[2] + col)
  child.api.nvim_input_mouse('right', 'release', '', 0, pos[1] + row, pos[2] + col)
end

local function settle()
  vim.wait(200)
  local mode = child.api.nvim_get_mode()
  child.api.nvim_input('<Esc>')
  H.wait(function() return not child.api.nvim_get_mode().blocking end, 2000, '关闭 popup 后输入循环必须恢复')
  return mode.mode
end

-- 普通窗口 A、带 buffer-local 右键映射的 B，以及 A 上方的普通窗口 C
local function build_layout()
  return lua([[
    require('config.options')
    require('config.keymaps.mouse')
    local lines = {}
    for i = 1, 10 do lines[i] = 'line ' .. i end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    local a = vim.api.nvim_get_current_win()
    vim.cmd('vnew')
    local b = vim.api.nvim_get_current_win()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.keymap.set('n', '<RightMouse>', function()
      local pos = vim.fn.getmousepos()
      _G.hit = { win = vim.api.nvim_get_current_win(), line = pos.line }
    end, { buffer = 0 })
    vim.api.nvim_set_current_win(a)
    vim.cmd('new')
    local c = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(a)
    vim.api.nvim_win_set_cursor(a, { 1, 0 })
    return { a = a, b = b, c = c }
  ]])
end

local function check_normal(mode)
  H.check(not mode:match('^[vV\22]'), '右键不能进入 visual，实际模式：' .. mode)
end

T['右键跨窗口分发且普通 buffer 不进 visual'] = function()
  local wins = build_layout()
  right_click(wins.b, 3, 2)
  settle()
  H.eq(lua('return _G.hit'), { win = wins.b, line = 4 },
    '点击未聚焦窗口必须在该窗口执行 buffer-local 映射，且定位到点击行')

  lua('vim.api.nvim_set_current_win(...); vim.api.nvim_win_set_cursor(0, { 1, 0 })', wins.a)
  right_click(wins.a, 5, 3)
  check_normal(settle())
  H.eq(lua('return vim.fn.mode()'), 'n', '关闭 popup 后必须保持 normal')
  H.eq(child.api.nvim_win_get_cursor(0), { 6, 3 }, '普通窗口右键必须把光标放到点击位置')

  lua('vim.api.nvim_set_current_win(...); _G.hit = nil', wins.c)
  right_click(wins.a, 2, 1)
  check_normal(settle())
  H.eq(child.api.nvim_get_current_win(), wins.a, '无专属映射时内置行为必须落到点击窗口')
  H.eq(lua('return _G.hit'), vim.NIL, '回退不能触发其他 buffer 的映射')
end

T['面板守卫不跨窗口执行且镜像窗口不循环'] = function()
  local wins = build_layout()
  local panel = lua([[
    local Mouse = require('vv-utils.mouse')
    vim.cmd('botright vnew')
    local p = vim.api.nvim_get_current_win()
    local lines = {}
    for i = 1, 10 do lines[i] = 'entry ' .. i end
    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
    vim.keymap.set('n', '<RightMouse>', function()
      if Mouse.redispatch_outside(p, '<RightMouse>') then return end
      _G.panel_hit = vim.fn.getmousepos().line
    end, { buffer = 0 })
    return p
  ]])
  right_click(wins.a, 3, 2)
  check_normal(settle())
  H.eq(lua('return _G.panel_hit'), vim.NIL, '从面板点击其他窗口不能执行面板动作')
  H.eq(child.api.nvim_get_current_win(), wins.a, '事件必须交还点击窗口')
  H.eq(child.api.nvim_win_get_cursor(0), { 4, 2 }, '转发右键必须保留点击位置')

  lua('vim.api.nvim_set_current_win(...)', panel)
  right_click(panel, 6, 1)
  settle()
  H.eq(lua('return _G.panel_hit'), 7, '面板内部右键仍须在点击行执行动作')

  local mirror = lua([[
    local p = ...
    vim.api.nvim_set_current_win(p)
    vim.cmd('split')
    local m = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(p)
    _G.panel_hit = nil
    return m
  ]], panel)
  right_click(mirror, 2, 1)
  settle()
  H.eq(lua('return _G.panel_hit'), vim.NIL, '同 buffer 的镜像窗口不能循环转发或执行面板动作')
end

return T
