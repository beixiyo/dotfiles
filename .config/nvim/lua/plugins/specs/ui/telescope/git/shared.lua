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

--- terminal preview 默认行数上限：预览只用于浏览，完整内容由各 picker 的打开动作提供
M.PREVIEW_LINE_CAP = 3000

--- 实际上限再收紧到 scrollback 的 80%，给终端折行与头尾提示行留余量
---@param line_cap integer
---@param scrollback integer
---@return integer
local function preview_cap(line_cap, scrollback)
  if scrollback <= 0 then
    return line_cap
  end
  return math.max(1, math.min(line_cap, math.floor(scrollback * 0.8)))
end

--- 通用 ANSI terminal previewer：命令输出经 nvim_open_term 渲染到 telescope preview buffer
--- 旧 job 先 stop，旧 chan 显式 close；回调比对 job_id，被终止的旧任务交付的缓冲输出自弃
---（stdout_buffered 下 jobstop 后仍可能交付一次，不比对会污染当前 entry 的 preview）
--- 骨架：jobstart 前先写一行灰色 Loading…，stdout 到达时先清屏归位再写（空输出也会清掉骨架）
--- 行数上限：terminal buffer 的 scrollback（默认 10000）装不下的输出会把头部顶掉，只剩尾部
--- 因此命令输出经 head 截断（SIGPIPE 同时提前终止上游，超大 diff 不再全量计算），
--- 多取 1 行精确判断是否截断，截断时在末尾追加灰色提示
---@param title string
---@param make_cmd function fun(entry: table, winid: number): string[] 返回完整 argv
---@param opts? TermPreviewerOpts
function M.term_previewer(title, make_cmd, opts)
  opts = opts or {}
  local line_cap = opts.line_cap == nil and M.PREVIEW_LINE_CAP or opts.line_cap
  local truncated_hint = opts.truncated_hint

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
      vim.api.nvim_chan_send(chan, '\27[90mLoading…\27[0m')

      local cmd = make_cmd(entry, winid)
      local cap = line_cap and preview_cap(line_cap, vim.bo[bufnr].scrollback)
      if cap then
        cmd = vim.list_extend({ 'bash', '-c', '"${@:2}" | head -n "$1"', '_', tostring(cap + 1) }, cmd)
      end

      local job_id
      job_id = vim.fn.jobstart(cmd, {
        stdout_buffered = true,
        on_stdout = function(_, data)
          if self.state.job_id ~= job_id then return end
          if not vim.api.nvim_buf_is_valid(bufnr) then return end

          local footer = ''
          if cap and #data - (data[#data] == '' and 1 or 0) > cap then
            data = vim.list_slice(data, 1, cap)
            footer = string.format('\r\n\27[90m… preview truncated to first %d lines%s\27[0m',
              cap, truncated_hint and ', ' .. truncated_hint or '')
          end

          vim.api.nvim_chan_send(chan, '\27[2J\27[H' .. table.concat(data, '\r\n') .. footer)
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

--- term_previewer 选项
---@class TermPreviewerOpts
---@field line_cap? integer|false 预览最多渲染的行数，`false` 不截断；实际值不超过 scrollback 的 80% @default M.PREVIEW_LINE_CAP
---@field truncated_hint? string 截断提示的补充说明，如查看完整内容的按键 @default nil

return M
