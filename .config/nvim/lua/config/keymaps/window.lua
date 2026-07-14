local h = require("config.keymaps.helpers")
local map, icons = h.map, h.icons

map("n", "<leader>-", "<C-w>s", {
  desc = icons.split_horizontal .. " " .. "Horizontal split",
  remap = true,
})
map("n", "<leader>|", "<C-w>v", {
  desc = icons.split_vertical .. " " .. "Vertical split",
  remap = true,
})
