-- git_commits + delta side-by-side 预览
-- telescope 每次 preview_fn 已创建新 buffer（无 get_buffer_by_name 时）
-- 直接在 self.state.bufnr 上 nvim_open_term，让 telescope 自己管 buffer 生命周期
local M = {}
local Git = require('plugins.specs.ui.telescope.git.shared')
local Keys = require('vv-utils.keys')

local log_limits = { 300, 2000, 10000, false }

local function open_file_tab(context)
  vim.cmd('tabnew ' .. vim.fn.fnameescape(context.abspath))
  local tabpage = vim.api.nvim_get_current_tabpage()
  local bufnr = vim.api.nvim_get_current_buf()
  local previous = vim.fn.maparg('Q', 'n', false, true)
  local restored = false

  if context.row then
    local row = math.min(context.row, vim.api.nvim_buf_line_count(bufnr))
    local target_line = vim.api.nvim_buf_get_lines(bufnr, row - 1, row, false)[1] or ''
    pcall(vim.api.nvim_win_set_cursor, 0, { row, math.min(context.col or 0, #target_line) })
    pcall(vim.cmd, 'normal! zz')
  end

  local function restore_mapping()
    if restored or not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end

    restored = true
    pcall(vim.keymap.del, 'n', 'Q', { buffer = bufnr })
    if type(previous) == 'table' and next(previous) then
      pcall(vim.fn.mapset, 'n', false, previous)
    end
  end

  local function return_to_vv_git()
    if vim.api.nvim_get_current_tabpage() ~= tabpage then
      return
    end

    local ok, err = pcall(vim.cmd, 'tabclose')
    if not ok then
      vim.notify(tostring(err), vim.log.levels.WARN)
    end
  end

  vim.keymap.set('n', 'Q', return_to_vv_git, {
    buffer = bufnr,
    silent = true,
    nowait = true,
    desc = 'Return to vv-git',
  })

  vim.api.nvim_create_autocmd('WinClosed', {
    pattern = tostring(vim.api.nvim_get_current_win()),
    once = true,
    callback = restore_mapping,
  })

  vim.notify('Press Q to return to vv-git', vim.log.levels.INFO)
end

local function next_log_limit(current)
  for index, limit in ipairs(log_limits) do
    if limit == current then
      return log_limits[index + 1]
    end
  end
end

function M.open(opts)
  local builtin = require('telescope.builtin')
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  opts = opts or {}
  local log_cwd = opts.cwd or vim.fn.getcwd()
  local git_root = require('vv-utils.git').root(opts.cwd)
  local log_limit = opts.git_log_limit

  if log_limit == nil then
    log_limit = log_limits[1]
  end

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
        if self.state.stat_job then
          pcall(self.state.stat_job.kill, self.state.stat_job, 15)
        end

        local bufnr = self.state.bufnr
        local winid = self.state.winid
        local width = vim.api.nvim_win_get_width(winid)
        local chan = vim.api.nvim_open_term(bufnr, {})

        self.state.stat_job = vim.system({
          'git',
          '-C',
          git_root,
          'show',
          '--numstat',
          '--format=',
          entry.value,
        }, { text = true }, function(result)
          vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(bufnr) then
              return
            end

            local added, deleted, binary_files = 0, 0, 0
            for line in (result.stdout or ''):gmatch('[^\r\n]+') do
              local a, d = line:match('^(%d+)\t(%d+)\t')
              if a then
                added = added + tonumber(a)
                deleted = deleted + tonumber(d)
              elseif line:match('^%-\t%-\t') then
                binary_files = binary_files + 1
              end
            end
            local binary = binary_files > 0 and string.format('  ·  %d binary', binary_files) or ''
            vim.api.nvim_chan_send(
              chan,
              string.format('\27[1mCommit changes\27[0m  \27[32m+%d\27[0m  \27[31m-%d\27[0m  ·  %d lines%s\r\n\r\n', added, deleted, added + deleted, binary)
            )

            self.state.job_id = vim.fn.jobstart({
              'bash',
              '-c',
              'git -C "$1" show --color=always "$2" | delta --side-by-side --width="$3"',
              '_',
              git_root,
              entry.value,
              tostring(width),
            }, {
              stdout_buffered = true,
              on_stdout = function(_, data)
                if not vim.api.nvim_buf_is_valid(bufnr) then
                  return
                end
                vim.api.nvim_chan_send(chan, table.concat(data, '\r\n'))
              end,
              on_exit = function()
                vim.schedule(function()
                  if not vim.api.nvim_buf_is_valid(bufnr) then
                    return
                  end

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
          end)
        end)
      end,
    })
  end

  opts.layout_config = { preview_width = 0.75 }
  local limit_label = log_limit and tostring(log_limit) or 'all'
  opts.prompt_title = table.concat({
    Keys.hint('Diff', '<CR>'),
    Keys.hint('RawDiff', '<C-o>'),
    Keys.hint('Hash', '<M-h>'),
    Keys.hint('Msg', '<M-y>'),
    Keys.hint('More', '<C-l>'),
    '[' .. limit_label .. ']',
  }, '  ')

  opts.attach_mappings = function(_, map)
    -- 在普通 buffer 中打开该 commit 的 diff（可 visual 选区复制，q/<Esc> 关闭并回到 telescope）。
    -- 同时覆盖 git_commits 默认的 <CR>=git checkout —— 看历史时误回车不再把当前 commit
    -- checkout 出去导致 HEAD 游离（detached）。
    local function open_diff(prompt_bufnr)
      local entry = action_state.get_selected_entry(prompt_bufnr)
      if not entry then
        return
      end

      actions.close(prompt_bufnr)
      Git.open_show_buffer(entry.value, function()
        require('telescope.builtin').resume()
      end)
    end

    -- <CR>：用 vv-git 的 commit diff 视图（commit^..commit，文件树 + 并排 diff，更好看），
    -- 不可用时回退到基础的 git show scratch buffer。无论哪种都不再 checkout（不会游离 HEAD）
    -- 必须用 select_default:replace 替换 action 对象，而非 map('<CR>', ...)
    -- 后者只是 keymap，telescope.builtin.resume() 重开 picker 后 action 对象会还原为默认的
    -- git_checkout，再按 <CR> 就 checkout 了 commit hash 导致 HEAD 游离。
    actions.select_default:replace(function(prompt_bufnr)
      local entry = action_state.get_selected_entry(prompt_bufnr)
      if not entry then
        return
      end

      local vvgit = Git.load_vv_git()
      if vvgit and type(vvgit.show_commit) == 'function' then
        local picker = action_state.get_current_picker(prompt_bufnr)
        local session = {
          cwd = log_cwd,
          default_text = picker:_get_prompt(),
          default_selection_index = entry.index,
          git_log_limit = log_limit,
        }
        actions.close(prompt_bufnr)
        -- 显式重建当前 git-log 会话，避免 vv-git 内其它 picker 覆盖 Telescope 的全局缓存。
        local resumed = false
        local function resume()
          if resumed then
            return
          end

          resumed = true
          M.open(session)
        end
        vvgit.show_commit(entry.value, {
          root = git_root,
          on_close = resume,
          on_goto_file = open_file_tab,
          on_error = function()
            if vvgit.is_open() then
              vvgit.close()
            end
            resume()
          end,
        })
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
      if not entry then
        return
      end
      Git.yank(entry.value, 'hash')
    end)

    -- 复制 commit 标题（留在 telescope）
    map({ 'i', 'n' }, '<M-y>', function(prompt_bufnr)
      local entry = action_state.get_selected_entry(prompt_bufnr)
      if not entry then
        return
      end
      Git.yank(Git.commit_subject(entry.value), 'message')
    end)

    return true
  end

  builtin.git_commits(opts)
end

return M
