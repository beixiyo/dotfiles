-- 验证右键契约：普通 buffer 右键不进 visual（不再是 mousemodel=extend）；
-- 焦点在别的窗口时右键点中带 buffer-local <RightMouse> 的窗口，该映射仍被调用且行定位正确
-- 用 --embed 子进程驱动真实鼠标输入（nvim_input_mouse 需经主循环的按键/映射解析，-l 进程内无法驱动）
local this = debug.getinfo(1, 'S').source:sub(2)
local H = dofile(vim.fs.find('harness.lua', { upward = true, path = vim.fs.dirname(this) })[1])

local chan = vim.fn.jobstart({ 'nvim', '--embed', '--headless', '--clean', '-n' }, { rpc = true })
H.check(chan > 0, 'failed to spawn embedded nvim')

local function lua(code, ...)
  return vim.rpcrequest(chan, 'nvim_exec_lua', code, { ... })
end

-- row / col 相对窗口文本区（跳过行号列等 textoff），与 getmousepos 的 line / column 对齐
local function right_click(win, row, col)
  local pos = lua('return vim.api.nvim_win_get_position(...)', win)
  col = col + lua('return vim.fn.getwininfo(...)[1].textoff', win)
  vim.rpcrequest(chan, 'nvim_input_mouse', 'right', 'press', '', 0, pos[1] + row, pos[2] + col)
  vim.rpcrequest(chan, 'nvim_input_mouse', 'right', 'release', '', 0, pos[1] + row, pos[2] + col)
end

-- 点击后取模式快照，再用 <Esc> 关掉可能弹出的 PopUp 菜单。菜单打开期间主循环阻塞在
-- 菜单输入上，nvim_exec_lua 会挂起，只有 nvim_get_mode 这类 fast API 可用，故先取快照再查状态
local function settle()
  vim.wait(200)
  local mode = vim.rpcrequest(chan, 'nvim_get_mode')
  vim.rpcrequest(chan, 'nvim_input', '<Esc>')
  vim.wait(100)
  return mode
end

local ok, err = pcall(function()
  lua([[
    local root = ...
    vim.opt.runtimepath:prepend(root)
    vim.opt.runtimepath:prepend(root .. '/vendors/vv-icons.nvim')
    require('config.options')
    require('config.keymaps.mouse')
  ]], H.root)

  -- 布局：左 A（普通 buffer），右 B（模拟 vv-git 面板：buffer-local <RightMouse> 读 getmousepos 定位行），
  -- A 上方再分出普通 buffer C
  local wins = lua([[
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

  -- 1. 焦点在 A，右键点 B 第 4 行：B 的 buffer-local 映射被调用，且行定位指向 B 的第 4 行
  right_click(wins.b, 3, 2)
  settle()
  H.eq(lua('return _G.hit'), { win = wins.b, line = 4 },
    'right click on an unfocused window must run its buffer-local <RightMouse> in that window, with getmousepos on the clicked line')

  -- 2. 普通 buffer 右键不扩展选区（不进 visual），且按 popup_setpos 把光标移到点击处
  lua('vim.api.nvim_set_current_win(...); vim.api.nvim_win_set_cursor(0, { 1, 0 })', wins.a)
  right_click(wins.a, 5, 3)
  local mode = settle().mode
  H.check(not mode:match('^[vV\22]'), 'right click in a plain buffer must not start a visual selection, got mode ' .. mode)
  H.eq(lua('return vim.fn.mode()'), 'n', 'closing the popup must leave normal mode')
  H.eq(lua('return vim.api.nvim_win_get_cursor(0)'), { 6, 3 }, 'popup_setpos right click must place the cursor at the click')

  -- 3. 焦点在 C，右键点无专属映射的 A：退回内置行为（不递归、不卡死），进入 A 且不进 visual
  lua('vim.api.nvim_set_current_win(...); _G.hit = nil', wins.c)
  right_click(wins.a, 2, 1)
  mode = settle().mode
  H.check(not mode:match('^[vV\22]'), 'cross-window right click without a buffer mapping must not start visual, got mode ' .. mode)
  H.eq(lua('return vim.api.nvim_get_current_win()'), wins.a, 'fallback right click must land in the clicked window')
  H.eq(lua('return _G.hit'), vim.NIL, 'fallback must not trigger another buffer mapping')

  -- 4. 反向：焦点在面板 P（buffer-local <RightMouse> 带 vv-utils.mouse.redispatch_outside 守卫），
  --    右键点普通窗口 A：面板动作不得执行（否则会拿 A 的行号操作面板），事件交还 A 走内置行为
  local panel = lua([[
    local root = ...
    vim.opt.runtimepath:prepend(root .. '/vendors/vv-utils.nvim')
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
  ]], H.root)
  lua('vim.api.nvim_set_current_win(...); _G.panel_hit = nil', panel)
  right_click(wins.a, 3, 2)
  mode = settle().mode
  H.check(not mode:match('^[vV\22]'), 'right click from a focused panel into another window must not start visual, got mode ' .. mode)
  H.eq(lua('return _G.panel_hit'), vim.NIL, 'panel right-click action must not run when the click lands in another window')
  H.eq(lua('return vim.api.nvim_get_current_win()'), wins.a, 'the click must be handed back to the clicked window')
  H.eq(lua('return vim.api.nvim_win_get_cursor(0)'), { 4, 2 }, 'the handed-back click must keep its mouse position')

  -- 点在面板内仍执行面板动作
  lua('vim.api.nvim_set_current_win(...)', panel)
  right_click(panel, 6, 1)
  settle()
  H.eq(lua('return _G.panel_hit'), 7, 'a click inside the panel must still run the panel action on the clicked line')

  -- 5. 同一面板 buffer 显示在两个窗口：点另一个窗口不得无限重发（settle 能返回即未卡死），也不执行动作
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
  H.eq(lua('return _G.panel_hit'), vim.NIL, 'a mirror window of the same panel buffer must not loop or run the action')
end)

pcall(vim.fn.jobstop, chan)
if not ok then error(err, 0) end
print('PASS: mouse right click dispatch')
