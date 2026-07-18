-- stash 管理：apply / pop / drop + delta diff 预览
-- stash push：push_all / push_staged / push_untracked / push_message
local M = {}

local function yank(text, label)
  vim.fn.setreg('+', text)
  vim.fn.setreg('"', text)
  vim.notify('已复制 ' .. label .. ': ' .. text, vim.log.levels.INFO)
end

---执行 git stash push 并弹通知
---@param args string[]   额外的 CLI 参数
---@param label string    通知前缀，如 "Stash created"
local function do_push(args, label)
  local cmd = vim.list_extend({ 'git', 'stash', 'push' }, args)
  local output = vim.fn.system(cmd)
  if vim.v.shell_error == 0 then
    vim.notify(label, vim.log.levels.INFO)
  else
    vim.notify('Stash push failed:\n' .. vim.trim(output), vim.log.levels.ERROR)
  end
end

--- 暂存所有已跟踪变更（working tree + index）
function M.push_all()
  do_push({}, 'Stash: 已暂存所有变更')
end

--- 只暂存 index（staged）区域，working tree 不动
function M.push_staged()
  do_push({ '--staged' }, 'Stash: 已暂存 staged 变更')
end

--- 暂存所有变更，包含 untracked 文件
function M.push_untracked()
  do_push({ '--include-untracked' }, 'Stash: 已暂存变更（含 untracked）')
end

--- 弹出输入框，以自定义消息暂存所有变更
function M.push_message()
  vim.ui.input({ prompt = 'Stash 描述: ' }, function(msg)
    if msg == nil then return end -- 按 Esc 取消
    local args = msg ~= '' and { '-m', msg } or {}
    do_push(args, 'Stash: 已创建 "' .. (msg ~= '' and msg or '(无描述)') .. '"')
  end)
end

function M.open(opts)
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  local previewers = require('telescope.previewers')
  opts = opts or {}

  local has_delta = vim.fn.executable('delta') == 1

  opts.previewer = previewers.new_buffer_previewer({
    title = 'Stash Diff',

    define_preview = function(self, entry)
      if self.state.job_id then
        pcall(vim.fn.jobstop, self.state.job_id)
      end

      local bufnr = self.state.bufnr
      local winid = self.state.winid
      local chan = vim.api.nvim_open_term(bufnr, {})
      local width = vim.api.nvim_win_get_width(winid)

      local cmd = 'git stash show -p --color=always ' .. vim.fn.shellescape(entry.value)
      if has_delta then
        cmd = cmd .. ' | delta --side-by-side --width=' .. width
      end

      self.state.job_id = vim.fn.jobstart({ 'bash', '-c', cmd }, {
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

  opts.layout_config = { preview_width = 0.65 }
  opts.prompt_title = 'Apply ↵  Pop ^X  Drop ^D'

  opts.attach_mappings = function(_, map)
    local function do_apply(prompt_bufnr)
      local entry = action_state.get_selected_entry(prompt_bufnr)
      if not entry then return end
      actions.close(prompt_bufnr)
      local output = vim.fn.system('git stash apply ' .. vim.fn.shellescape(entry.value))
      if vim.v.shell_error == 0 then
        vim.notify('Stash applied: ' .. entry.value, vim.log.levels.INFO)
      else
        vim.notify('Apply failed: ' .. vim.trim(output), vim.log.levels.ERROR)
      end
    end

    map({ 'i', 'n' }, '<CR>', do_apply)

    map({ 'i', 'n' }, '<C-x>', function(prompt_bufnr)
      local entry = action_state.get_selected_entry(prompt_bufnr)
      if not entry then return end
      actions.close(prompt_bufnr)
      local output = vim.fn.system('git stash pop ' .. vim.fn.shellescape(entry.value))
      if vim.v.shell_error == 0 then
        vim.notify('Stash popped: ' .. entry.value, vim.log.levels.INFO)
      else
        vim.notify('Pop failed: ' .. vim.trim(output), vim.log.levels.ERROR)
      end
    end)

    map({ 'i', 'n' }, '<C-d>', function(prompt_bufnr)
      local entry = action_state.get_selected_entry(prompt_bufnr)
      if not entry then return end
      actions.close(prompt_bufnr)
      local output = vim.fn.system('git stash drop ' .. vim.fn.shellescape(entry.value))
      if vim.v.shell_error == 0 then
        vim.notify('Stash dropped: ' .. entry.value, vim.log.levels.INFO)
        vim.schedule(function() M.open() end)
      else
        vim.notify('Drop failed: ' .. vim.trim(output), vim.log.levels.ERROR)
      end
    end)

    map({ 'i', 'n' }, '<M-h>', function(prompt_bufnr)
      local entry = action_state.get_selected_entry(prompt_bufnr)
      if not entry then return end
      yank(entry.value, 'stash ref')
    end)

    return true
  end

  require('telescope.builtin').git_stash(opts)
end

return M
