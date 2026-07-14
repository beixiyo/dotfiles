local Util = require("tokyonight.util")

local M = {}

-- map of plugin name to plugin extension
--- @type table<string, {ext:string, url:string, label:string, subdir?: string, sep?:string}>
M.extras = {
  vim              = { ext = "vim", url = "https://vimhelp.org/", label = "Vim", subdir = "colors", sep = "-" },
}

function M.setup()
  local tokyonight = require("tokyonight.theme")
  vim.o.background = "dark"

  -- map of style to style name
  local styles = {
    moon = " Moon",
    pretty_moon = " Pretty Moon",
    pretty_cat = " Pretty Cat",
  }

  ---@type string[]
  local names = vim.tbl_keys(M.extras)
  table.sort(names)

  for _, extra in ipairs(names) do
    local info = M.extras[extra]
    local plugin = require("tokyonight.extra." .. extra)
    for style, style_name in pairs(styles) do
      local colors, groups, opts = tokyonight.setup({ style = style, plugins = { all = true } })
      local fname = extra
        .. (info.subdir and "/" .. info.subdir .. "/" or "")
        .. "/tokyonight"
        .. (info.sep or "_")
        .. style
        .. "."
        .. info.ext
      fname = string.gsub(fname, "%.$", "") -- remove trailing dot when no extension
      colors["_upstream_url"] = "https://github.com/folke/tokyonight.nvim/raw/main/extras/" .. fname
      colors["_style_name"] = "Tokyo Night" .. style_name
      colors["_name"] = "tokyonight_" .. style
      colors["_style"] = style
      print("[write] " .. fname)
      Util.write("extras/" .. fname, plugin.generate(colors, groups, opts))
    end
  end
end
M.setup()

return M
