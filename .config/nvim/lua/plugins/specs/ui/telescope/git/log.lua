-- git_commits + delta side-by-side 预览
-- telescope 每次 preview_fn 已创建新 buffer（无 get_buffer_by_name 时）
-- 直接在 self.state.bufnr 上 nvim_open_term，让 telescope 自己管 buffer 生命周期
local M = {}
local Git = require('plugins.specs.ui.telescope.git.shared')
local Keys = require('vv-utils.keys')

local log_limits = { 300, 2000, 10000, false }

-- 统计头与 diff 走同一条管道：统计头排在第 1 行并计入 term_previewer 的行数上限，
-- 超大 commit 截断时只丢 diff 尾部；同一个 job 也让过期守卫一并覆盖统计阶段
local preview_script = [[
git -C "$1" show --numstat --format= "$2" | awk -F '\t' '
  $1 == "-" { binary++; next }
  NF >= 3 { added += $1; deleted += $2 }
  END {
    printf "\033[1mCommit changes\033[0m  \033[32m+%d\033[0m  \033[31m-%d\033[0m  ·  %d lines", added, deleted, added + deleted
    if (binary) printf "  ·  %d binary", binary
    printf "\n\n"
  }'
git -C "$1" show --color=always "$2" | delta --side-by-side --width="$3"
]]

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
    opts.previewer = Git.term_previewer('Git Log', function(entry, winid)
      return {
        'bash',
        '-c',
        preview_script,
        '_',
        git_root,
        entry.value,
        tostring(vim.api.nvim_win_get_width(winid)),
      }
    end, {
      truncated_hint = 'press <CR> for the full commit view',
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
    -- 在普通 buffer 中打开该 commit 的 diff（可 visual 选区复制，q/<Esc> 关闭并回到 telescope）
    -- 同时覆盖 git_commits 默认的 <CR>=git checkout —— 看历史时误回车不再把当前 commit
    -- checkout 出去导致 HEAD 游离（detached）
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
    -- git_checkout，再按 <CR> 就 checkout 了 commit hash 导致 HEAD 游离
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
        -- 显式重建当前 git-log 会话，避免 vv-git 内其它 picker 覆盖 Telescope 的全局缓存
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

    -- 分档扩大历史范围，避免大型仓库首次打开时一次性读取完整日志
    -- 重开 picker 时保留当前搜索词；到达全部历史后不再重复刷新
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
