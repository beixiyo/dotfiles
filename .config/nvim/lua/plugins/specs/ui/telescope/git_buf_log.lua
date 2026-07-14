-- 当前 buffer 的 git commit 历史 + delta 预览，选中后 diff 对比
local M = {}

local function yank(text, label)
  vim.fn.setreg('+', text)
  vim.fn.setreg('"', text)
  vim.notify('已复制 ' .. label .. ': ' .. text, vim.log.levels.INFO)
end

local function open_in_buf(hash, on_close)
  local lines = vim.fn.systemlist('git show ' .. hash)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = 'diff'
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = 'wipe'

  vim.cmd('botright split')
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_buf_set_name(buf, hash:sub(1, 7) .. ' diff')

  for _, key in ipairs({ 'q', '<Esc>' }) do
    vim.keymap.set('n', key, function()
      vim.api.nvim_win_close(win, true)
      if on_close then vim.schedule(on_close) end
    end, { buffer = buf, nowait = true })
  end
end

local function make_delta_previewer()
  if vim.fn.executable('delta') == 0 then return nil end
  local previewers = require('telescope.previewers')

  return previewers.new_buffer_previewer({
    title = 'Git Buffer Log',

    define_preview = function(self, entry)
      if self.state.job_id then
        pcall(vim.fn.jobstop, self.state.job_id)
      end

      local bufnr = self.state.bufnr
      local winid = self.state.winid
      local width = vim.api.nvim_win_get_width(winid)
      local chan = vim.api.nvim_open_term(bufnr, {})

      self.state.job_id = vim.fn.jobstart({
        'bash', '-c',
        'git show --color=always ' .. entry.value .. ' | delta --side-by-side --width=' .. width,
      }, {
        stdout_buffered = true,
        on_stdout = function(_, data)
          if not vim.api.nvim_buf_is_valid(bufnr) then return end
          vim.api.nvim_chan_send(chan, table.concat(data, '\r\n'))
        end,
        on_exit = function()
          vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(bufnr) then return end
            pcall(function()
              vim.bo[bufnr].scrollback = 9999
              vim.bo[bufnr].scrollback = 9998
            end)
            if vim.api.nvim_win_is_valid(winid) then
              pcall(vim.api.nvim_win_set_cursor, winid, { 1, 0 })
            end
          end)
        end,
      })
    end,
  })
end

local function open_diff(rev, source_win, reopen)
  local source_buf = vim.api.nvim_win_get_buf(source_win)
  local filepath = vim.api.nvim_buf_get_name(source_buf)
  if filepath == '' then return end

  local toplevel = vim.trim(vim.fn.system('git rev-parse --show-toplevel'))
  local rel = filepath:sub(#toplevel + 2)
  local content = vim.fn.systemlist({ 'git', 'show', rev .. ':' .. rel })
  if vim.v.shell_error ~= 0 then
    vim.notify('git show failed: ' .. rev .. ':' .. rel, vim.log.levels.WARN)
    return
  end

  local diff_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(diff_buf, 0, -1, false, content)
  vim.bo[diff_buf].bufhidden = 'wipe'
  vim.bo[diff_buf].modifiable = false

  local ft = vim.bo[source_buf].filetype
  if ft ~= '' then vim.bo[diff_buf].filetype = ft end

  vim.api.nvim_set_current_win(source_win)
  vim.cmd('leftabove vsplit')
  local diff_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(diff_win, diff_buf)
  vim.api.nvim_buf_set_name(diff_buf, rev:sub(1, 7) .. ':' .. vim.fn.fnamemodify(rel, ':t'))

  vim.wo[diff_win].foldenable = false
  vim.wo[source_win].foldenable = false

  vim.cmd('diffthis')
  vim.api.nvim_set_current_win(source_win)
  vim.cmd('diffthis')

  local function close()
    vim.cmd('diffoff!')
    if vim.api.nvim_win_is_valid(diff_win) then
      vim.api.nvim_win_close(diff_win, true)
    end
    vim.wo[source_win].foldenable = true
    pcall(vim.keymap.del, 'n', 'q', { buffer = source_buf })
    pcall(vim.keymap.del, 'n', '<Esc>', { buffer = source_buf })
    vim.schedule(reopen)
  end

  for _, buf in ipairs({ diff_buf, source_buf }) do
    vim.keymap.set('n', 'q', close, { buffer = buf })
    vim.keymap.set('n', '<Esc>', close, { buffer = buf })
  end
end

function M.open(opts)
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  opts = opts or {}
  opts.previewer = make_delta_previewer() or opts.previewer

  local source_win = vim.api.nvim_get_current_win()

  opts.attach_mappings = function(_, map)
    actions.select_default:replace(function(prompt_bufnr)
      local entry = action_state.get_selected_entry(prompt_bufnr)
      actions.close(prompt_bufnr)
      if not entry then return end
      open_diff(entry.value, source_win, function() require('telescope.builtin').resume() end)
    end)

    -- 复制 commit hash（留在 telescope）
    map({ 'i', 'n' }, '<M-h>', function(prompt_bufnr)
      local entry = action_state.get_selected_entry(prompt_bufnr)
      if not entry then return end
      yank(entry.value, 'hash')
    end)

    -- 复制 commit 标题（留在 telescope）
    map({ 'i', 'n' }, '<M-y>', function(prompt_bufnr)
      local entry = action_state.get_selected_entry(prompt_bufnr)
      if not entry then return end
      local subject = vim.trim(vim.fn.system('git log -1 --format=%s ' .. entry.value))
      yank(subject, 'message')
    end)

    -- 在普通 buffer 中打开 diff（可 visual 选区复制，q/<Esc> 关闭并回到 telescope）
    map({ 'i', 'n' }, '<C-o>', function(prompt_bufnr)
      local entry = action_state.get_selected_entry(prompt_bufnr)
      if not entry then return end
      actions.close(prompt_bufnr)
      open_in_buf(entry.value, function() require('telescope.builtin').resume() end)
    end)

    return true
  end

  opts.layout_config = { preview_width = 0.75 }
  opts.prompt_title = 'CR:diff  C-o:raw-diff  M-h:hash  M-y:msg'
  require('telescope.builtin').git_bcommits(opts)
end

return M
