local h = require("config.keymaps.helpers")
local map, icons = h.map, h.icons

map("n", "<A-Down>", "<cmd>m .+1<cr>==", { desc = icons.move_down .. " " .. "Move line down" })
map("n", "<A-Up>", "<cmd>m .-2<cr>==", { desc = icons.move_up .. " " .. "Move line up" })

map("v", "<A-Down>", ":m '>+1<cr>gv=gv", { desc = icons.move_down .. " " .. "Move selection down" })
map("v", "<A-Up>", ":m '<-2<cr>gv=gv", { desc = icons.move_up .. " " .. "Move selection up" })

map("n", "<Tab>", ">>", { desc = icons.cursor .. " " .. "Indent line" })
map("n", "<S-Tab>", "<<", { desc = icons.cursor .. " " .. "Outdent line" })
map("x", "<Tab>", ">gv", { desc = icons.cursor .. " " .. "Indent selection" })
map("x", "<S-Tab>", "<gv", { desc = icons.cursor .. " " .. "Outdent selection" })

map("n", "d", '"_d', { desc = "Delete without yanking" })
map("n", "D", '"_D', { desc = "Delete to line end" })
map("n", "c", '"_c', { desc = "Change without yanking" })
map("n", "C", '"_C', { desc = "Change to line end" })
map("n", "x", '"_x', { desc = "Delete character" })
map("n", "X", '"_X', { desc = "Delete previous character" })

map("x", "d", '"_d', { desc = "Delete selection" })
map("x", "D", '"_D', { desc = "Delete selected lines" })
map("x", "c", '"_c', { desc = "Change selection" })
map("x", "C", '"_C', { desc = "Change selected lines" })
map("x", "x", '"+x', { desc = "Cut to clipboard" })
map("x", "X", '"_X', { desc = "Delete selection backward" })
