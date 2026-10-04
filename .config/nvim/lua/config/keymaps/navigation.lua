local h = require("config.keymaps.helpers")
local map, icons = h.map, h.icons

map({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", { expr = true })
map({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", { expr = true })
-- 当前行是否在窗口里折成多行：只有折行时 $ / A / I 才改用屏幕行版本，
-- 否则走原生键，保留 . 重复（A,<Esc> 后在别的行 . 仍追加到行尾）与 $ 的列粘滞
local function line_wraps()
  if not vim.wo.wrap then return false end
  local info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
  return vim.fn.virtcol("$") - 1 > info.width - info.textoff
end

map({ "n", "x" }, "$", function()
  return (vim.v.count == 0 and line_wraps()) and "g$" or "$"
end, { expr = true })

-- expr 直接返回按键：不用 feedkeys 补发（会排到已输入的键之后，I-<Esc> 这类连续输入会乱序）
-- 折行时 g^i 在屏幕行第一个非空字符处插入
map("n", "I", function()
  return (vim.v.count == 0 and line_wraps()) and "g^i" or "I"
end, { expr = true, desc = "Insert at display line start" })
map("n", "A", function()
  return (vim.v.count == 0 and line_wraps()) and "g$a" or "A"
end, { expr = true, desc = "Append at display line end" })

map("n", "n", "nzz", { desc = "Next match" })
map("n", "N", "Nzz", { desc = "Previous match" })
map("n", "*", "*zz", { desc = "Find word forward" })
map("n", "#", "#zz", { desc = "Find word backward" })

map("n", "<A-Left>", "<C-o>", { desc = icons.prev .. " " .. "Previous jump" })
map("n", "<A-Right>", "<C-i>", { desc = icons.next .. " " .. "Next jump" })

-- <C-e>/<C-y>：hover 文档（vv-hover 浮窗 / 原生 K 的 noice hover）打开时滚动文档，
-- 否则滚当前窗。一律走 vv-utils.scroll 平滑滚动（不自己造轮子；保留 count，如 3<C-e>）
local function scroll_hover_or_buffer(dir)
  local scroll = require("vv-utils.scroll")
  local lines = vim.v.count > 0 and vim.v.count or (scroll.get_config().step or 5)
  local signed = dir == "down" and lines or -lines

  -- 1) vv-hover 鼠标浮窗：平滑滚浮窗（不进窗）
  local ok_vw, vw = pcall(require, "vv-hover.view")
  if ok_vw and vw.is_open and vw.is_open() then
    local fwin = vw.get_current()
    if fwin and vim.api.nvim_win_is_valid(fwin) then
      scroll.window(fwin, signed)
      return
    end
  end

  -- 2) noice hover（K 弹出的文档）：用 noice 自带 popup 滚动
  local ok_n, nlsp = pcall(require, "noice.lsp")
  if ok_n and nlsp.scroll(dir == "down" and 4 or -4) then
    return
  end

  -- 3) 回退：vv-utils 平滑滚动当前窗
  scroll.window(vim.api.nvim_get_current_win(), signed)
end

map("n", "<C-e>", function() scroll_hover_or_buffer("down") end, { desc = "Scroll down" })
map("n", "<C-y>", function() scroll_hover_or_buffer("up") end, { desc = "Scroll up" })
