local map = require("config.keymaps.helpers").map

local function extend_selection_to_mouse()
  local pos = vim.fn.getmousepos()
  if not pos or not pos.winid or pos.winid == 0 then
    return
  end
  if vim.api.nvim_get_current_win() ~= pos.winid then
    vim.api.nvim_set_current_win(pos.winid)
  end
  local line = pos.line
  local col = math.max(0, (pos.column or 1) - 1)
  local mode = vim.fn.mode(true):sub(1, 1)
  if mode == "n" then
    vim.cmd("normal! v")
    vim.api.nvim_win_set_cursor(pos.winid, { line, col })
  elseif mode == "v" or mode == "V" or mode == "\22" then
    vim.api.nvim_win_set_cursor(pos.winid, { line, col })
  end
end

map({ "n", "x" }, "<S-LeftMouse>", extend_selection_to_mouse, { desc = "Extend selection" })

map("i", "<S-LeftMouse>", function()
  local pos = vim.fn.getmousepos()
  if not pos or not pos.winid or pos.winid == 0 then
    return
  end
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>v", true, false, true), "nx", false)
  if vim.api.nvim_get_current_win() ~= pos.winid then
    vim.api.nvim_set_current_win(pos.winid)
  end
  pcall(vim.api.nvim_win_set_cursor, pos.winid, { pos.line, math.max(0, (pos.column or 1) - 1) })
end, { desc = "Extend selection" })

local RIGHT_MOUSE = vim.keycode("<RightMouse>")

local function has_buf_right_mouse(buf)
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
    if vim.keycode(m.lhs) == RIGHT_MOUSE then
      return true
    end
  end
  return false
end

-- 跨窗口右键分发：buffer-local 鼠标映射只按「当前 buffer」查找，焦点在别处时右键点进面板
-- （如 vv-git 文件树的暂存/取消暂存）会落到源窗口的映射上。点中窗口的 buffer 有专属
-- <RightMouse> 时先切过去再重新分发（'m' 可重映射，命中该 buffer-local 映射，鼠标坐标不变）；
-- 否则以 noremap 重发，交回内置 popup_setpos 行为，不会再进本映射。仅 normal 模式，visual / insert 保持内置
map("n", "<RightMouse>", function()
  local pos = vim.fn.getmousepos()
  local win = pos.winid
  if
    win ~= 0
    and win ~= vim.api.nvim_get_current_win()
    and has_buf_right_mouse(vim.api.nvim_win_get_buf(win))
    and pcall(vim.api.nvim_set_current_win, win)
  then
    vim.api.nvim_feedkeys(RIGHT_MOUSE, "mi", false)
    return
  end
  vim.api.nvim_feedkeys(RIGHT_MOUSE, "ni", false)
end, { desc = "Right click dispatch" })
