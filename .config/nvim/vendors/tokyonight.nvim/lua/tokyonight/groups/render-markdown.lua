local Util = require("tokyonight.util")

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
    RenderMarkdownTableHead  = { fg = c.red },
    RenderMarkdownTableRow   = { fg = c.orange },
    RenderMarkdownCodeInline = "@markup.raw.markdown_inline",
  }
  for i = 1, #c.rainbow do
    ret["RenderMarkdownH" .. i .. "Bg"] = { bg = Util.blend_bg(heading_color, 0.1) }
    ret["RenderMarkdownH" .. i .. "Fg"] = { fg = heading_color, bold = true }
  end
  return ret
end

return M
