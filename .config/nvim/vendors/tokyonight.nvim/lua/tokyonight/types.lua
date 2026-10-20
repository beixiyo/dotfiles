---@class tokyonight.Highlight: vim.api.keyset.highlight
---@field style? vim.api.keyset.highlight

---@alias tokyonight.Highlights table<string,tokyonight.Highlight|string>

---@alias tokyonight.HighlightsFn fun(colors: ColorScheme, opts:tokyonight.Config):tokyonight.Highlights

---@class tokyonight.Cache
---@field groups tokyonight.Highlights
---@field inputs table

---@class tokyonight.StylesOptions
---@field comments? vim.api.keyset.highlight
---@field keywords? vim.api.keyset.highlight
---@field functions? vim.api.keyset.highlight
---@field variables? vim.api.keyset.highlight
---@field sidebars? 'dark'|'transparent'|'normal'
---@field floats? 'dark'|'transparent'|'normal'

---@class tokyonight.ConfigOptions
---@field style? string
---@field light_style? string
---@field transparent? boolean
---@field terminal_colors? boolean
---@field styles? tokyonight.StylesOptions
---@field day_brightness? number
---@field dim_inactive? boolean
---@field lualine_bold? boolean
---@field cache? boolean
---@field plugins? table<string, boolean|{enabled:boolean}>
---@field on_colors? fun(colors: ColorScheme)
---@field on_highlights? fun(highlights: tokyonight.Highlights, colors: ColorScheme)
