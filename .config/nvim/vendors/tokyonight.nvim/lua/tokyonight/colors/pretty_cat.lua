-- Pretty Cat：pretty_dark 调色板 + catppuccin mocha 背景梯度
-- bg / bg_dark / bg_dark1 / bg_highlight / fg_gutter / terminal_black 来自 mocha；
-- 其余语义色全部从 pretty_dark 继承。
-- 用法：tokyonight.load({ style = "pretty_cat" })

local pretty_dark = require("tokyonight.colors.pretty_dark")

---@class Palette
local ret = vim.tbl_deep_extend("force", pretty_dark, {
  -- ── 背景梯度（catppuccin mocha 灰紫底）
  bg           = "#1e1e2e", -- 主背景（base）
  bg_dark      = "#181825", -- sidebar / popup（mantle）
  bg_dark1     = "#11111b", -- 最深档（crust）
  bg_highlight = "#313244", -- 当前行高亮（surface0）

  -- ── 辅助色
  fg_gutter      = "#45475a", -- mocha surface1
  terminal_black = "#585b70", -- mocha surface2
})

return ret
