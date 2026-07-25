local FindFiles = require('plugins.specs.ui.telescope.toggles.find_files')
local GrepString = require('plugins.specs.ui.telescope.toggles.grep_string')
local LiveGrep = require('plugins.specs.ui.telescope.toggles.live_grep')

local M = {}

M.find_files = FindFiles.open
M.grep_string = GrepString.open
M.live_grep = LiveGrep.open

return M
