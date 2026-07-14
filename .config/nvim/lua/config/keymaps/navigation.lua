local h = require("config.keymaps.helpers")
local map, icons = h.map, h.icons

map({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", { expr = true })
map({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", { expr = true })
map({ "n", "x" }, "$", "v:count == 0 ? 'g$' : '$'", { expr = true })
map({ "n", "x" }, "0", "v:count == 0 ? 'g0' : '0'", { expr = true })

map("n", "I", function()
  if vim.v.count > 0 then
    vim.api.nvim_feedkeys(vim.v.count .. "I", "n", false)
    return
  end
  vim.cmd("normal! g0")
  local lnum, col = vim.fn.line("."), vim.fn.col(".")
  local idx = vim.fn.getline("."):find("%S", col)
  if idx then
    vim.api.nvim_win_set_cursor(0, { lnum, idx - 1 })
  end
  vim.cmd("startinsert")
end, { desc = "Insert at display line start" })
map("n", "A", "v:count == 0 ? 'g$a' : 'A'", { expr = true, desc = "Append at display line end" })

map("n", "n", "nzz", { desc = "Next match" })
map("n", "N", "Nzz", { desc = "Previous match" })
map("n", "*", "*zz", { desc = "Find word forward" })
map("n", "#", "#zz", { desc = "Find word backward" })

map("n", "<A-Left>", "<C-o>", { desc = icons.prev .. " " .. "Previous jump", remap = true })
map("n", "<A-Right>", "<C-i>", { desc = icons.next .. " " .. "Next jump", remap = true })

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
