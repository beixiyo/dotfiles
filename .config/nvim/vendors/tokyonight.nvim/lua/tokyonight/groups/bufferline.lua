local M = {}

M.url = "https://github.com/akinsho/bufferline.nvim"

---@type tokyonight.HighlightsFn
function M.get(c, opts)
  -- 注：bufferline 的活动 tab 底色由 plugins/ui/bufferline.lua 的 highlights option 控制
  -- 这里只保留 tokyonight 原有的 indicator 颜色定义作为兜底
  -- stylua: ignore
  return {
    BufferLineIndicatorSelected = { fg = c.git.change },
  }
end

return M
