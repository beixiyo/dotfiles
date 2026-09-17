local M = {}

function M.yank(text, label)
  vim.fn.setreg('+', text)
  vim.fn.setreg('"', text)
  vim.notify('Copied ' .. label .. ': ' .. text, vim.log.levels.INFO)
end

--- 异步 git job，exit code 是唯一成败信号
--- stderr 只累积不即时通知：成功丢弃（git push/fetch 非 TTY 下正常输出也走 stderr），失败并入 ERROR 通知
--- on_exit_msg(code) 返回 nil 时跳过基础通知；on_success 仅 code==0 执行；on_finally 无论 code 都执行
---（已 schedule，on_finally 用于删除失败后的事后校验等收尾）
---@param args string[]         完整 argv（走 execvp，不经 shell）
---@param on_exit_msg function? fun(code: number): string?
---@param on_success function?  fun()
---@param on_finally function?  fun(code: number)
function M.git_async(args, on_exit_msg, on_success, on_finally)
  local stderr_lines = {}
  vim.fn.jobstart(args, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stderr = function(_, data)
      for _, l in ipairs(data or {}) do
        if l ~= '' then stderr_lines[#stderr_lines + 1] = l end
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        local msg = on_exit_msg and on_exit_msg(code) or nil
        if code ~= 0 and #stderr_lines > 0 then
          local detail = table.concat(stderr_lines, '\n')
          msg = msg and (msg .. '\n' .. detail) or detail
        end
        if msg then
          vim.notify(msg, code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR)
        end
        if code == 0 and on_success then on_success() end
        if on_finally then on_finally(code) end
      end)
    end,
  })
end

--- 通用 ANSI terminal previewer：命令输出经 nvim_open_term 渲染到 telescope preview buffer
--- 旧 job 先 stop，旧 chan 显式 close；回调比对 job_id，被终止的旧任务交付的缓冲输出自弃
---（stdout_buffered 下 jobstop 后仍可能交付一次，不比对会污染当前 entry 的 preview）
---@param title string
---@param make_cmd function fun(entry: table, winid: number): string[] 返回完整 argv
function M.term_previewer(title, make_cmd)
  local previewers = require('telescope.previewers')
  return previewers.new_buffer_previewer({
    title = title,
    define_preview = function(self, entry)
      if self.state.job_id then
        pcall(vim.fn.jobstop, self.state.job_id)
      end
      if self.state.chan then
        pcall(vim.fn.chanclose, self.state.chan)
      end

      local bufnr = self.state.bufnr
      local winid = self.state.winid
      local chan = vim.api.nvim_open_term(bufnr, {})
      self.state.chan = chan

      local job_id
      job_id = vim.fn.jobstart(make_cmd(entry, winid), {
        stdout_buffered = true,
        on_stdout = function(_, data)
          if self.state.job_id ~= job_id then return end
          if not vim.api.nvim_buf_is_valid(bufnr) then return end
          vim.api.nvim_chan_send(chan, table.concat(data, '\r\n'))
        end,
        on_exit = function()
          vim.schedule(function()
            if self.state.job_id ~= job_id then return end
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
      self.state.job_id = job_id
    end,
  })
end

function M.open_show_buffer(hash, on_close)
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

function M.load_vv_git()
  local ok, vvgit = pcall(require, 'vv-git')
  if ok then return vvgit end
  if vim.fn.exists(':VVGitLoad') == 2 then pcall(vim.cmd, 'VVGitLoad') end
  ok, vvgit = pcall(require, 'vv-git')
  return ok and vvgit or nil
end

function M.commit_subject(hash)
  return vim.trim(vim.fn.system('git log -1 --format=%s ' .. hash))
end

return M
