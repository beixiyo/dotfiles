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

local function load_vv_git()
  local ok, vvgit = pcall(require, 'vv-git')
  if ok then return vvgit end

  if vim.fn.exists(':VVGitLoad') == 2 then
    pcall(vim.cmd, 'VVGitLoad')
  end

  ok, vvgit = pcall(require, 'vv-git')
  return ok and vvgit or nil
end

function M.open(opts)
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  opts = opts or {}
  opts.previewer = make_delta_previewer() or opts.previewer

  local source_buf = vim.api.nvim_get_current_buf()

  opts.attach_mappings = function(_, map)
    actions.select_default:replace(function(prompt_bufnr)
      local entry = action_state.get_selected_entry(prompt_bufnr)
      if not entry then return end

      local vvgit = load_vv_git()
      if not vvgit or type(vvgit.compare_file) ~= 'function' then
        vim.notify('vv-git does not support compare_file', vim.log.levels.ERROR)
        return
      end

      actions.close(prompt_bufnr)
      vvgit.compare_file(entry.value, {
        bufnr = source_buf,
        on_close = function() require('telescope.builtin').resume() end,
      })
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
