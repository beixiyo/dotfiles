local h = require("config.keymaps.helpers")
local map, icons = h.map, h.icons

map("v", "<C-c>", '"+y', { desc = icons.copy .. " " .. "Copy to clipboard" })
