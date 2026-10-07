-- 编辑区定向查看：在行列上限内创建分屏或复用相邻窗口，保持焦点
-- 用户配置：只需修改这两个正整数；例如 2 行 × 3 列最多 6 个文件窗口
local MAX_ROWS = 2
local MAX_COLUMNS = 2
local layout_label = ("%d×%d"):format(MAX_COLUMNS, MAX_ROWS)
local h = require("config.keymaps.helpers")
local map, icons = h.map, h.icons

map("n", "<leader>-", function()
  require("tools.editor-split").show({ axis = "horizontal", max_rows = MAX_ROWS, max_columns = MAX_COLUMNS })
end, {
  desc = icons.split_horizontal .. " " .. "View in other row (" .. layout_label .. ")",
})
map("n", "<leader>|", function()
  require("tools.editor-split").show({ axis = "vertical", max_rows = MAX_ROWS, max_columns = MAX_COLUMNS })
end, {
  desc = icons.split_vertical .. " " .. "View in other column (" .. layout_label .. ")",
})
