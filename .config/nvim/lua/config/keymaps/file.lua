local h = require("config.keymaps.helpers")
local map, icons = h.map, h.icons
local scratch = require('config.scratch')

scratch.setup()

map("n", "<leader>W", "<cmd>W<cr>", { desc = icons.save .. " " .. "Write as sudo" })
map({ "n", "x" }, "<leader>fy", "<cmd>CopyPathLine<cr>", { desc = icons.copy .. " " .. "Copy location" })

map("n", "<leader>bn", function()
  vim.cmd.VVScratchNew()
end, { desc = icons.new_file .. " " .. "New scratch buffer" })

map({ "x", "n", "s" }, "<C-A-s>", "<cmd>wa<cr><esc>", { desc = icons.save .. " " .. "Save all" })
map("i", "<C-A-s>", "<cmd>wa<cr>", { desc = icons.save .. " " .. "Save all" })
map({ "x", "n", "s" }, "<C-s>", "<cmd>w<cr><esc>", { desc = icons.save .. " " .. "Save file" })
map("i", "<C-s>", "<cmd>w<cr>", { desc = icons.save .. " " .. "Save file" })
