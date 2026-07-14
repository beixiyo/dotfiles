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
