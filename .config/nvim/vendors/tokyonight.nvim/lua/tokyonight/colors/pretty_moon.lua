-- Pretty Moon：pretty_dark 调色板 + tokyo-moon 背景梯度
-- bg / bg_dark / bg_dark1 / bg_highlight / terminal_black / fg_gutter 来自 moon；
-- 其余语义色全部从 pretty_dark 继承。
-- 用法：tokyonight.load({ style = "pretty_moon" })

local pretty_dark = require("tokyonight.colors.pretty_dark")

---@class Palette
local ret = vim.tbl_deep_extend("force", pretty_dark, {
  -- ── 背景梯度（tokyo-moon 冷蓝底）
  bg           = "#222436", -- 主背景（moon）
  bg_dark      = "#1e2030", -- sidebar / popup（moon）
  bg_dark1     = "#191B29", -- 最深档（moon）
  bg_highlight = "#2f334d", -- 当前行高亮（moon）

  -- ── 辅助色
  fg_gutter      = "#3b4261", -- moon
  terminal_black = "#444a73", -- moon
})

return ret
