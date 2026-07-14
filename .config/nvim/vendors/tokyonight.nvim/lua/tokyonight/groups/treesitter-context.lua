local M = {}

M.url = "https://github.com/nvim-treesitter/nvim-treesitter-context"

---@type tokyonight.HighlightsFn
function M.get(c)
  -- 顶部粘性上下文：去掉整块底色,只留一条下边线作为"边界"(参考 Pretty Dark)
  -- stylua: ignore
  return {
    TreesitterContext                    = { bg = c.none },
    TreesitterContextLineNumber          = { fg = c.dark5, bg = c.none },
    TreesitterContextBottom              = { sp = c.border, underline = true },
    TreesitterContextLineNumberBottom    = { sp = c.border, underline = true },
  }
end

return M
