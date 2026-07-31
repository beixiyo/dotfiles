local source = debug.getinfo(1, 'S').source:sub(2)
local root = vim.fn.fnamemodify(source, ':p:h:h')
local utils_root = root .. '/vendors/vv-utils.nvim'

vim.opt.runtimepath:prepend(utils_root)
vim.opt.runtimepath:prepend(root)

local fs = require('vv-utils.fs')
local scratch = require('config.scratch')

local function check(condition, message)
  if not condition then error(message, 0) end
end

local function edit_scratch(content)
  scratch.new('md')
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { content })
  vim.bo[buf].modified = true
  vim.api.nvim_exec_autocmds('TextChanged', { buffer = buf, modeline = false })
  return buf, path
end

scratch.setup()

local success_buf, success_path = edit_scratch('debounced')
check(vim.bo[success_buf].modified, 'debounce queue cleared modified before persistence')
check(vim.wait(1000, function() return fs.read_all(success_path) == 'debounced\n' end),
  'debounced autosave did not persist buffer contents')
check(not vim.bo[success_buf].modified, 'successful debounced autosave did not clear modified')

local stale_buf, stale_path = edit_scratch('editor')
vim.cmd.enew()
fs.write_all(stale_path, 'external\n')
vim.wait(600)
check(fs.read_all(stale_path) == 'external\n',
  'a stale debounce overwrote a newer external write after BufLeave flush')

vim.api.nvim_set_current_buf(stale_buf)
vim.api.nvim_buf_set_lines(stale_buf, 0, -1, false, { 'future-autosave' })
vim.bo[stale_buf].modified = true
vim.api.nvim_exec_autocmds('TextChanged', { buffer = stale_buf, modeline = false })
check(vim.wait(1000, function() return fs.read_all(stale_path) == 'future-autosave\n' end),
  'invalidating the stale debounce broke a later autosave')
check(not vim.bo[stale_buf].modified, 'later autosave did not clear modified after success')

vim.api.nvim_buf_set_lines(stale_buf, 0, -1, false, { 'write-failure' })
vim.bo[stale_buf].modified = true
vim.api.nvim_exec_autocmds('TextChanged', { buffer = stale_buf, modeline = false })

local scratch_dir = vim.fs.dirname(stale_path)
local original_mode = assert(vim.uv.fs_stat(scratch_dir)).mode % 4096
assert(vim.uv.fs_chmod(scratch_dir, 365))
local switched = pcall(vim.cmd.enew)
assert(vim.uv.fs_chmod(scratch_dir, original_mode))

check(not switched, 'BufLeave write failure did not block an ordinary buffer switch')
check(vim.api.nvim_get_current_buf() == stale_buf, 'write failure left the dirty scratch buffer')
check(vim.bo[stale_buf].modified, 'write failure cleared modified')

vim.bo[stale_buf].modified = false
vim.api.nvim_buf_delete(stale_buf, { force = true })
if vim.api.nvim_buf_is_valid(success_buf) then
  vim.bo[success_buf].modified = false
  vim.api.nvim_buf_delete(success_buf, { force = true })
end
pcall(fs.delete, success_path)
pcall(fs.delete, stale_path)

print('PASS: scratch persistence, stale debounce invalidation, and write-failure safety')
