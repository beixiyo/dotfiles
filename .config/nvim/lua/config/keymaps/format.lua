local h = require("config.keymaps.helpers")
local map, icons = h.map, h.icons

map({ "n", "x" }, "<leader>cs", function() require("vv-utils").format.add_spaces({ silent = true }) end, {
  desc = icons.words .. " " .. "Add CJK spacing",
})
map({ "n", "x" }, "<leader>c.", function() require("vv-utils").format.clean_trailing({ silent = true }) end, {
  desc = icons.cursor .. " " .. "Clean line endings",
})
