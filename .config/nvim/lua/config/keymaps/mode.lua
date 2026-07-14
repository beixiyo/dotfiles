local h = require("config.keymaps.helpers")
local map, icons = h.map, h.icons

map("i", "jk", "<Esc>", { desc = icons.exit_insert .. " " .. "Exit insert mode" })
