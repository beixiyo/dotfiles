-- tokyonight 调色板访问：集中「从 colors_name 解析当前 style」这处易错逻辑
-- 历史上这里写过不存在的 vim.g.tokyonight_style，收口避免再次漂移
-- 注：palette 的取法因用途而异（原始色板 vs setup 解析后的完整色），故只共用 style 检测

---@class tools.palette
local M = {}

--- 当前激活的 tokyonight style，从 vim.g.colors_name 解析（形如 "tokyonight-moon"）
---@param fallback? string 解析失败时的兜底 style @default 'pretty_dark'
---@return string
function M.style(fallback)
  return (vim.g.colors_name or ''):match('^tokyonight%-(.+)$') or fallback or 'pretty_dark'
end

--- 当前 style 的原始调色板（lualine / bufferline 用，取色后自行组合 highlight）
---@return Palette
function M.get()
  local ok, p = pcall(require, 'tokyonight.colors.' .. M.style())
  return ok and p or require('tokyonight.colors.pretty_dark')
end

return M
