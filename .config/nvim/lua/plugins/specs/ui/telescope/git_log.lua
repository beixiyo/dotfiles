-- git_commits + delta side-by-side 预览
-- telescope 每次 preview_fn 已创建新 buffer（无 get_buffer_by_name 时）
-- 直接在 self.state.bufnr 上 nvim_open_term，让 telescope 自己管 buffer 生命周期
local M = {}

local log_limits = { 300, 2000, 10000, false }

local function next_log_limit(current)
  for index, limit in ipairs(log_limits) do
    if limit == current then
      return log_limits[index + 1]
    end
  end
end

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
  local builtin = require('telescope.builtin')
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  opts = opts or {}
  local log_limit = opts.git_log_limit

  if log_limit == nil then log_limit = log_limits[1] end

  opts.git_command = {
    'git',
    'log',
    '--pretty=oneline',
    '--abbrev-commit',
  }

  if log_limit then
    table.insert(opts.git_command, '--max-count=' .. log_limit)
  end

  vim.list_extend(opts.git_command, { '--', '.' })

  if vim.fn.executable('delta') == 1 then
    local previewers = require('telescope.previewers')

    opts.previewer = previewers.new_buffer_previewer({
      title = 'Git Log',

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

  opts.layout_config = { preview_width = 0.75 }
  local limit_label = log_limit and tostring(log_limit) or 'all'
  opts.prompt_title = 'Diff ↵  Raw diff ^O  Hash ⌥H  Message ⌥Y  More ^L  [' .. limit_label .. ']'

  opts.attach_mappings = function(_, map)
    -- 在普通 buffer 中打开该 commit 的 diff（可 visual 选区复制，q/<Esc> 关闭并回到 telescope）。
    -- 同时覆盖 git_commits 默认的 <CR>=git checkout —— 看历史时误回车不再把当前 commit
    -- checkout 出去导致 HEAD 游离（detached）。
    local function open_diff(prompt_bufnr)
      local entry = action_state.get_selected_entry(prompt_bufnr)
      if not entry then return end
      actions.close(prompt_bufnr)
      open_in_buf(entry.value, function() require('telescope.builtin').resume() end)
    end

    -- <CR>：用 vv-git 的 commit diff 视图（commit^..commit，文件树 + 并排 diff，更好看），
    -- 不可用时回退到基础的 git show scratch buffer。无论哪种都不再 checkout（不会游离 HEAD）
    -- 必须用 select_default:replace 替换 action 对象，而非 map('<CR>', ...)
    -- 后者只是 keymap，telescope.builtin.resume() 重开 picker 后 action 对象会还原为默认的
    -- git_checkout，再按 <CR> 就 checkout 了 commit hash 导致 HEAD 游离。
    actions.select_default:replace(function(prompt_bufnr)
      local entry = action_state.get_selected_entry(prompt_bufnr)
      if not entry then return end
      local vvgit = load_vv_git()
      if vvgit and type(vvgit.show_commit) == 'function' then
        actions.close(prompt_bufnr)
        -- 按 q 关闭 vv-git 面板后，自动 resume 回到这个 git_log telescope 列表
        vvgit.show_commit(entry.value, function() require('telescope.builtin').resume() end)
      else
        open_diff(prompt_bufnr)
      end
    end)
    map({ 'i', 'n' }, '<C-o>', open_diff)

    -- 分档扩大历史范围，避免大型仓库首次打开时一次性读取完整日志。
    -- 重开 picker 时保留当前搜索词；到达全部历史后不再重复刷新。
    map({ 'i', 'n' }, '<C-l>', function(prompt_bufnr)
      local next_limit = next_log_limit(log_limit)
      if next_limit == nil then
        vim.notify('All Git history is loaded', vim.log.levels.INFO)
        return
      end

      local picker = action_state.get_current_picker(prompt_bufnr)
      local default_text = picker:_get_prompt()
      actions.close(prompt_bufnr)

      vim.schedule(function()
        M.open({
          git_log_limit = next_limit,
          default_text = default_text,
        })
      end)
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

    return true
  end

  builtin.git_commits(opts)
end

return M
