-- 持久化 scratch buffer，并在普通离开或退出时阻止写入失败导致的数据丢失
-- `:qa!` 属于显式强制退出边界，可能忽略 autocmd 错误，因此不承诺持久化

local fs = require('vv-utils.fs')
local timer = require('vv-utils.timer')

local M = {}

local augroup = vim.api.nvim_create_augroup('config_scratch', { clear = true })
local scratch_dir = fs.realpath(vim.fn.stdpath('state') .. '/scratch')
local autosave_by_buf = {}
local did_setup = false
local scratch_seq = 0

-- 停止输入后多久自动落盘（毫秒）
local AUTOSAVE_DELAY_MS = 500
-- 空 buffer 经 :update 落盘是 0 字节，早期直接写文件的版本是一个 '\n'，因此 <= 1 字节视为空文件
local EMPTY_FILE_MAX_SIZE = 1

local function normalize_ext(ext)
  ext = vim.trim(ext or '')
  ext = ext:gsub('^%.+', '')

  if ext == '' then
    return nil
  end
  if not ext:match('^[%w_.-]+$') then
    return nil
  end

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
    if not vim.uv.fs_stat(path) then
      return path
    end
  end

  error('cannot allocate scratch filename')
end

---解析 `scratch-<date>-<time>-<seq>.<ext>`，兼容手动恢复出来的 `recovered-scratch-*` 命名
local function parse_scratch_name(name)
  local base = name:match('^recovered%-(.+)$') or name
  local year, month, day, hour, minute, second, ext = base:match('^scratch%-(%d%d%d%d)(%d%d)(%d%d)%-(%d%d)(%d%d)(%d%d)%-%d+%.([%w_.-]+)$')
  if not year then
    return nil
  end

  return {
    ext = ext,
    timestamp = os.time({
      year = tonumber(year),
      month = tonumber(month),
      day = tonumber(day),
      hour = tonumber(hour),
      min = tonumber(minute),
      sec = tonumber(second),
    }),
  }
end

---目录不存在时 `readdir` 会打 E484，这里静默返回空表
local function readdir_or_empty(dir)
  if vim.fn.isdirectory(dir) ~= 1 then
    return {}
  end

  return vim.fn.readdir(dir)
end

---列出 scratch 目录里所有由本模块命名规则创建、且仍在磁盘上的草稿，按创建时间倒序
---@return ScratchEntry[]
function M.list()
  local entries = {}

  for _, name in ipairs(readdir_or_empty(scratch_dir)) do
    local parsed = parse_scratch_name(name)
    local path = scratch_dir .. '/' .. name
    local stat = vim.uv.fs_stat(path)
    if parsed and stat and stat.type == 'file' then
      entries[#entries + 1] = {
        empty = stat.size <= EMPTY_FILE_MAX_SIZE,
        ext = parsed.ext,
        name = name,
        path = path,
        size = stat.size,
        timestamp = parsed.timestamp,
      }
    end
  end

  table.sort(entries, function(a, b)
    return a.timestamp > b.timestamp
  end)
  return entries
end

---磁盘文件的 mtime 签名，用于识别其他写入者（另一个 Neovim 实例等）改过文件
---@return string|nil
local function disk_signature(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return nil
  end

  return ('%d.%09d'):format(stat.mtime.sec, stat.mtime.nsec)
end

---记录当前磁盘状态为“本 buffer 已知的最新版本”，并解除冲突暂停
local function remember_disk(buf)
  local state = autosave_by_buf[buf]
  if not state then
    return
  end

  state.disk_signature = disk_signature(vim.api.nvim_buf_get_name(buf))
  state.conflict = false
end

local function cancel_autosave(buf)
  local state = autosave_by_buf[buf]
  if not state then
    return
  end

  pcall(state.cancel)
  autosave_by_buf[buf] = nil
end

local function write_buffer(buf)
  local state = autosave_by_buf[buf]
  if state then
    state.revision = state.revision + 1
  end

  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  -- 已卸载（如 :bd 之后）的 buffer 读不到任何行，落盘只会把文件清空
  if not vim.api.nvim_buf_is_loaded(buf) then
    return
  end
  if vim.bo[buf].buftype ~= '' then
    return
  end

  local path = vim.api.nvim_buf_get_name(buf)
  if not is_scratch_path(path) then
    return
  end
  if vim.b[buf].scratch_deleting then
    return
  end

  -- 磁盘被其他写入者改过（典型是另一个 Neovim 实例），本 buffer 的内容可能已过期，
  -- 覆盖会丢数据；暂停自动保存，等用户 :e 重新读取或 :w! 明确覆盖
  if state and disk_signature(path) ~= state.disk_signature then
    if not state.conflict then
      state.conflict = true
      vim.notify('Scratch changed on disk by another writer, autosave paused (use :e to reload or :w! to overwrite): ' .. path, vim.log.levels.WARN)
    end
    return
  end

  -- 用 Neovim 自己的写入而不是直接写文件：同步 buffer 的文件时间戳（否则之后手动 :w 会弹
  -- “文件已被修改”确认）、并顺带写出 undofile，重新打开后 `u` 才能真正恢复；
  -- noautocmd 跳过格式化等 BufWrite 钩子，update 只在有改动时落盘
  vim.api.nvim_buf_call(buf, function()
    vim.cmd('silent noautocmd keepalt update')
  end)

  if state then
    state.disk_signature = disk_signature(path)
  end
  if vim.api.nvim_buf_is_valid(buf) then
    vim.bo[buf].modified = false
  end
end

local function write_all_buffers()
  for buf in pairs(autosave_by_buf) do
    write_buffer(buf)
  end
end

local function attach_autosave(buf)
  if autosave_by_buf[buf] then
    return
  end

  local path = vim.api.nvim_buf_get_name(buf)
  if not is_scratch_path(path) then
    return
  end

  vim.b[buf].is_scratch_file = true

  local debounced, cancel = timer.debounce(function(target_buf, revision)
    local state = autosave_by_buf[target_buf]
    if not state or state.revision ~= revision then
      return
    end

    local ok, err = pcall(write_buffer, target_buf)
    if not ok then
      vim.notify('Scratch autosave failed: ' .. tostring(err), vim.log.levels.ERROR)
    end
  end, AUTOSAVE_DELAY_MS)

  autosave_by_buf[buf] = {
    debounced = debounced,
    cancel = cancel,
    revision = 0,
  }
end

local function schedule_autosave(buf)
  local state = autosave_by_buf[buf]
  if not state then
    return
  end

  state.revision = state.revision + 1
  state.debounced(buf, state.revision)
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
    if ext ~= nil then
      M.new(ext)
    end
  end)
end

---找到已加载该文件的 buffer（按 realpath 比较），没有则返回 nil
local function find_buf(path)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) and fs.realpath(vim.api.nvim_buf_get_name(buf)) == path then
      return buf
    end
  end
  return nil
end

---删除指定草稿文件；若它已在某个 buffer 里打开，先停掉自动保存再一并关闭
---@param path string
---@return boolean ok
---@return string|nil err
function M.delete(path)
  path = fs.realpath(path)
  if not is_scratch_path(path) then
    return false, 'not a scratch file: ' .. path
  end

  local buf = find_buf(path)
  if buf then
    cancel_autosave(buf)
    vim.b[buf].scratch_deleting = true
  end

  local ok, err = pcall(fs.delete, path)
  if not ok then
    return false, tostring(err)
  end

  if buf then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  -- 顺手清掉持久化 undo 文件，否则会在 undo 目录里永久残留
  local undo_path = vim.fn.undofile(path)
  if undo_path ~= '' and vim.uv.fs_stat(undo_path) then
    pcall(fs.delete, undo_path)
  end
  return true
end

function M.delete_current()
  local path = vim.api.nvim_buf_get_name(0)

  if path == '' or not is_scratch_path(path) then
    vim.notify('Current buffer is not a scratch file', vim.log.levels.WARN)
    return
  end

  local ok, err = M.delete(path)
  if not ok then
    vim.notify('Scratch delete failed: ' .. err, vim.log.levels.ERROR)
    return
  end
  vim.notify('Scratch deleted: ' .. path, vim.log.levels.INFO)
end

function M.setup()
  if did_setup then
    return
  end
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
      -- 首次打开和 :e 重新读取都以此刻的磁盘为准
      remember_disk(event.buf)
    end,
  })

  -- 补全菜单可见时 Neovim 触发的是 TextChangedP 而不是 TextChangedI，缺了它会等到 InsertLeave 才保存
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'TextChangedP', 'InsertLeave' }, {
    group = augroup,
    callback = function(event)
      schedule_autosave(event.buf)
    end,
  })

  vim.api.nvim_create_autocmd('BufLeave', {
    group = augroup,
    callback = function(event)
      if event.buf and autosave_by_buf[event.buf] then
        write_buffer(event.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd('QuitPre', {
    group = augroup,
    -- 普通退出会在写失败时中止；:qa! 明确要求 Neovim 强制退出，
    -- 可能忽略 autocmd 错误，因此不承诺强制退出或进程终止时持久化
    callback = write_all_buffers,
  })

  vim.api.nvim_create_autocmd({ 'BufWritePost' }, {
    group = augroup,
    callback = function(event)
      if is_scratch_path(vim.api.nvim_buf_get_name(event.buf)) then
        local state = autosave_by_buf[event.buf]
        if state then
          state.revision = state.revision + 1
        end
        remember_disk(event.buf)
        vim.bo[event.buf].modified = false
      end
    end,
  })

  vim.api.nvim_create_autocmd({ 'BufUnload' }, {
    group = augroup,
    callback = function(event)
      if autosave_by_buf[event.buf] then
        write_buffer(event.buf)
      end
    end,
  })

  vim.api.nvim_create_autocmd({ 'VimLeavePre' }, {
    group = augroup,
    callback = write_all_buffers,
  })

  vim.api.nvim_create_autocmd({ 'BufWipeout' }, {
    group = augroup,
    callback = function(event)
      cancel_autosave(event.buf)
    end,
  })
end

return M

---@class ScratchAutosaveState
---@field debounced fun(buf: integer, revision: integer)
---@field cancel fun()
---@field revision integer
---@field disk_signature? string 最近一次本 buffer 读取或写入后的磁盘 mtime 签名
---@field conflict? boolean 磁盘被其他写入者改过，自动保存已暂停

---@class ScratchEntry
---@field empty boolean 文件内容为空（建了没写，或写了又清空）
---@field ext string
---@field name string
---@field path string
---@field size integer
---@field timestamp integer 从文件名解析出的创建时间
