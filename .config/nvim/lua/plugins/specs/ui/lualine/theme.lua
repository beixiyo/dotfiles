-- palette 只管编辑器；lualine 配色集中在此，避免通过回退链与编辑器 fg 耦合
-- 跟随当前激活的 tokyonight style，避免切换主题后色板错位
local p = require('tools').palette.get()

local bg_edge   = p.bg_highlight   -- b / y
local bg_middle = p.bg        -- c / x
local fg_text   = '#c2c2c2'
local fg_muted  = p.fg_gutter

local function a(bg) return { bg = bg, fg = '#000000', gui = 'bold' } end
local function b(fg) return { bg = bg_edge, fg = fg } end
local function c_section() return { bg = bg_middle, fg = fg_text } end

return {
  normal   = { a = a(p.blue),    b = b(p.blue),    c = c_section() },
  insert   = { a = a(p.green),   b = b(p.green) },
  command  = { a = a(p.yellow),  b = b(p.yellow) },
  visual   = { a = a(p.magenta), b = b(p.magenta) },
  replace  = { a = a(p.red),     b = b(p.red) },
  terminal = { a = a(p.green1),  b = b(p.green1) },
  inactive = {
    a = { bg = bg_middle, fg = p.blue },
    b = { bg = bg_middle, fg = fg_muted, gui = 'bold' },
    c = { bg = bg_middle, fg = fg_muted },
  },
}
