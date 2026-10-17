local M = {}

M.url = "https://github.com/MeanderingProgrammer/render-markdown.nvim"

---@type tokyonight.HighlightsFn
function M.get(c, opts)
  -- stylua: ignore
  local heading_color = "#e06c75"
  local ret = {
    RenderMarkdownBullet     = { fg = "#6f9bff" },
    RenderMarkdownCode       = { bg = c.bg_dark },
    RenderMarkdownDash       = { fg = "#6f9bff" },
    -- 表格线框：head / row 同色且低调；header 文字颜色由 treesitter 的 @markup.heading 提供
    RenderMarkdownTableHead  = { fg = c.terminal_black },
    RenderMarkdownTableRow   = { fg = c.terminal_black },
    RenderMarkdownCodeInline = "@markup.raw.markdown_inline",
  }
  -- 标题分级：H1、H2 红，H3 蓝，H4+ 中性，靠明度而非色相拉开层级
  local levels = {
    { fg = heading_color },
    { fg = heading_color },
    { fg = c.blue },
    { fg = c.fg_dark },
    { fg = c.fg_dark },
    { fg = c.fg_dark },
  }
  for i, h in ipairs(levels) do
    ret["RenderMarkdownH" .. i .. "Fg"] = { fg = h.fg, bold = true }
  end
  return ret
end

return M
