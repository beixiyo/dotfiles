local fs = require('vv-utils.fs')
local timer = require('vv-utils.timer')

local M = {}

local augroup = vim.api.nvim_create_augroup('config_scratch', { clear = true })
local scratch_dir = fs.realpath(vim.fn.stdpath('state') .. '/scratch')
local autosave_by_buf = {}
local did_setup = false
local scratch_seq = 0

local function normalize_ext(ext)
  ext = vim.trim(ext or '')
  ext = ext:gsub('^%.+', '')

  if ext == '' then return nil end
  if not ext:match('^[%w_.-]+$') then return nil end

  return ext
end

local function is_scratch_path(path)
  path = fs.realpath(path or '')
  return path == scratch_dir or path:sub(1, #scratch_dir + 1) == scratch_dir .. '/'
end

local function scratch_path(ext)
  local stamp = os.date('%Y%m%d-%H%M%S')

  for _ = 1, 999 do
    scratch_seq = scratch_seq + 1

    local path = ('%s/scratch-%s-%03d.%s'):format(scratch_dir, stamp, scratch_seq, ext)
    if not vim.uv.fs_stat(path) then return path end
  end

  error('cannot allocate scratch filename')
end

local function lines_for_write(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  return table.concat(lines, '\n') .. '\n'
end

local function cancel_autosave(buf)
  local state = autosave_by_buf[buf]
  if not state then return end

  pcall(state.cancel)
  autosave_by_buf[buf] = nil
end

local function write_buffer(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  if vim.bo[buf].buftype ~= '' then return end

  local path = vim.api.nvim_buf_get_name(buf)
  if not is_scratch_path(path) then return end
  if vim.b[buf].scratch_deleting then return end

  fs.write_all(path, lines_for_write(buf))

  if vim.api.nvim_buf_is_valid(buf) then
    vim.bo[buf].modified = false
  end
end

local function attach_autosave(buf)
  if autosave_by_buf[buf] then return end

  local path = vim.api.nvim_buf_get_name(buf)
  if not is_scratch_path(path) then return end

  vim.b[buf].is_scratch_file = true

  local debounced, cancel = timer.debounce(function(target_buf)
    local ok, err = pcall(write_buffer, target_buf)
    if not ok then
      vim.notify('Scratch autosave failed: ' .. tostring(err), vim.log.levels.ERROR)
    end
  end, 400)

  autosave_by_buf[buf] = {
    debounced = debounced,
    cancel = cancel,
  }
end

local function schedule_autosave(buf)
  local state = autosave_by_buf[buf]
  if not state then return end

  state.debounced(buf)

  if vim.api.nvim_buf_is_valid(buf) then
    vim.bo[buf].modified = false
  end
end

function M.new(ext)
  ext = normalize_ext(ext or 'md')
  if not ext then
    vim.notify('Invalid scratch extension', vim.log.levels.WARN)
    return
  end

  local path = scratch_path(ext)
  fs.write_all(path, '')

  vim.cmd.edit(vim.fn.fnameescape(path))
  attach_autosave(vim.api.nvim_get_current_buf())
end

function M.prompt_new()
  vim.ui.input({ prompt = 'ext (e.g. ts, lua): ', default = 'md' }, function(ext)
    if ext ~= nil then M.new(ext) end
  end)
end

function M.delete_current()
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)

  if path == '' or not is_scratch_path(path) then
    vim.notify('Current buffer is not a scratch file', vim.log.levels.WARN)
    return
  end

  cancel_autosave(buf)
  vim.b[buf].scratch_deleting = true
  fs.delete(path)

  pcall(vim.api.nvim_buf_delete, buf, { force = true })
  vim.notify('Scratch deleted: ' .. path, vim.log.levels.INFO)
end

function M.setup()
  if did_setup then return end
  did_setup = true

  vim.api.nvim_create_user_command('VVScratchNew', function(opts)
    if opts.args == '' then
      M.prompt_new()
      return
    end

    M.new(opts.args)
  end, {
    nargs = '?',
    desc = '新建可自动保存的临时文件',
  })

  vim.api.nvim_create_user_command('VVScratchDelete', function()
    M.delete_current()
  end, {
    desc = '删除当前临时文件并关闭 buffer',
  })

  vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufNewFile' }, {
    group = augroup,
    callback = function(event)
      attach_autosave(event.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'InsertLeave' }, {
    group = augroup,
    callback = function(event)
      schedule_autosave(event.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufLeave', 'QuitPre' }, {
    group = augroup,
    callback = function(event)
      if event.buf and autosave_by_buf[event.buf] then
        pcall(write_buffer, event.buf)
        return
      end

      for buf in pairs(autosave_by_buf) do
        pcall(write_buffer, buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufWritePost' }, {
    group = augroup,
    callback = function(event)
      if is_scratch_path(vim.api.nvim_buf_get_name(event.buf)) then
        vim.bo[event.buf].modified = false
      end
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufUnload' }, {
    group = augroup,
    callback = function(event)
      if autosave_by_buf[event.buf] then
        pcall(write_buffer, event.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ 'VimLeavePre' }, {
    group = augroup,
    callback = function()
      for buf in pairs(autosave_by_buf) do
        pcall(write_buffer, buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufWipeout' }, {
    group = augroup,
    callback = function(event)
      cancel_autosave(event.buf)
    end,
  })
end

return M
