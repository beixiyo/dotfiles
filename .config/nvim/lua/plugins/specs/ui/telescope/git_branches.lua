-- 分支管理：本地+远程统一显示，时间排序+分级高亮
-- 本地分支在上，远程分支在下，各自按 committerdate 降序
-- 全局 defaults 把 C-d/C-r/C-y 绑成了 preview scroll，attach_mappings 里显式重绑回来
-- 所有 git 操作走 git_async，notify 短句英文（不用 telescope 内置 action，前缀太长）
-- C-a 新建分支：vim.ui.input 弹名字，以选中分支为起点 checkout -b
-- CR checkout 远程分支时自动建本地 tracking branch（避免 detached HEAD）
-- 删除/合并/rebase 用 vim.fn.confirm 单键 y/n 确认（参照 vv-explorer，无需回车）
-- 本地/远程一律用 entry.is_remote 判断，parse_remote 仅在确定远程后用于拆 remote/branch
-- （含 / 的本地分支如 feat/login 不能靠 parse_remote 判别，否则会被误当远程）
local M = {}

-- ── 高亮 ────────────────────────────────────────────────────────────────────

local _hl_ok = false
local function ensure_hl()
  if _hl_ok then return end
  _hl_ok = true
  require('vv-utils.hl').register('vv.git-branches.hl', {
    VVBranchHead   = { fg = '#e06c75', bold = true },  -- 当前分支的 * 标记，红
    VVBranchMain   = { fg = '#e06c75', bold = true },  -- main/master  红
    VVBranchFeat   = { fg = '#d19a66', bold = true },  -- feat*        橙
    VVBranchDev    = { fg = '#61afef', bold = true },  -- dev*         蓝
    VVBranchTest   = { fg = '#98c379', bold = true },  -- test*        绿
    VVBranchRemote = { fg = '#c678dd' },               -- 其他远程分支 紫
    VVBranchLocal  = { fg = '#abb2bf' },               -- 其他本地分支 灰白
    VVBranchAge1h  = { fg = '#56d364', bold = true },  -- < 1h   亮绿
    VVBranchAge12h = { fg = '#e3b341' },               -- < 12h  金黄
    VVBranchAge3d  = { fg = '#79c0ff' },               -- < 3d   浅蓝
    VVBranchAge7d  = { fg = '#768390' },               -- < 7d   灰蓝
    VVBranchAgeOld = { fg = '#444c56' },               -- ≥ 7d   暗灰
  })
end

-- 按分支名匹配高亮组；优先级：main/master > test > dev > feat > 其他(远程紫/本地灰白)
-- 远程分支先剥掉 remote 名（首段）再判类型；本地分支用全名判类型
-- （本地 feat/login 若也剥首段会得到 login → 丢失 feat 类型，故必须分流）
local function branch_hl(name, is_remote)
  local base = is_remote and (name:match('^[^/]+/(.+)$') or name) or name
  if base == 'main' or base == 'master' then return 'VVBranchMain' end
  if base:match('^test')                then return 'VVBranchTest' end
  if base:match('^dev')                 then return 'VVBranchDev'  end
  if base:match('^feat')                then return 'VVBranchFeat' end
  return is_remote and 'VVBranchRemote' or 'VVBranchLocal'
end

-- ── 时间工具 ─────────────────────────────────────────────────────────────────

local function time_fmt(ts)
  return os.date('%m-%d %H:%M:%S', ts)
end

local function time_hl(ts)
  local d = os.time() - ts
  if d < 3600       then return 'VVBranchAge1h'  end
  if d < 3600 * 12  then return 'VVBranchAge12h' end
  if d < 86400 * 3  then return 'VVBranchAge3d'  end
  if d < 86400 * 7  then return 'VVBranchAge7d'  end
  return 'VVBranchAgeOld'
end

-- ── 数据获取 ─────────────────────────────────────────────────────────────────

-- vim.fn.systemlist 传 table 走 execvp，不经过 shell，tab 字符不会被拆分
local function query_refs(ref_path)
  return vim.fn.systemlist({
    'git', 'for-each-ref',
    '--sort=-committerdate',
    '--format=%(refname:short)\t%(committerdate:unix)\t%(HEAD)\t%(subject)',
    ref_path,
  })
end

local function parse_lines(lines, is_remote)
  local result = {}
  for _, line in ipairs(lines) do
    local name, ts_str, head, subject = line:match('^([^\t]+)\t(%d+)\t([^\t]*)\t(.*)')
    if not name then goto continue end
    if name:match('/HEAD$') then goto continue end
    -- 过滤裸 remote 名（如 "origin"，不含 /）
    if is_remote and not name:find('/', 1, true) then goto continue end
    local ts = tonumber(ts_str) or 0
    result[#result + 1] = {
      name      = name,
      ts        = ts,
      is_head   = head == '*',
      is_remote = is_remote,
      subject   = subject or '',
      time_str  = time_fmt(ts),
      time_hl   = time_hl(ts),
      branch_hl = branch_hl(name, is_remote),
    }
    ::continue::
  end
  return result
end

local function get_branches()
  local local_b  = parse_lines(query_refs('refs/heads'),   false)
  local remote_b = parse_lines(query_refs('refs/remotes'),  true)
  local all = {}
  for _, e in ipairs(local_b)  do all[#all + 1] = e end
  for _, e in ipairs(remote_b) do all[#all + 1] = e end
  return all
end

-- ── 杂项 ─────────────────────────────────────────────────────────────────────

local function yank(text)
  vim.fn.setreg('+', text)
  vim.fn.setreg('"', text)
  vim.notify('Copied: ' .. text, vim.log.levels.INFO)
end

local function parse_remote(name)
  return name:match('^([^/]+)/(.+)$')
end

-- 单键 y/n 确认（默认 No），参照 vv-explorer 删除弹窗
local function confirm(question)
  return vim.fn.confirm(question, '&Yes\n&No', 2) == 1
end

-- on_exit_msg(code) 返回 nil 时跳过通知；on_success 在 code==0 时（已 schedule）执行
local function git_async(args, on_exit_msg, on_success)
  vim.fn.jobstart(args, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stderr = function(_, data)
      local lines = vim.tbl_filter(function(l) return l ~= '' end, data or {})
      if #lines > 0 then
        vim.schedule(function()
          vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
        end)
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if on_exit_msg then
          local msg = on_exit_msg(code)
          if msg then
            local level = code == 0 and vim.log.levels.INFO or vim.log.levels.ERROR
            vim.notify(msg, level)
          end
        end
        if code == 0 and on_success then on_success() end
      end)
    end,
  })
end

-- ── picker ───────────────────────────────────────────────────────────────────

function M.open(opts)
  ensure_hl()

  local action_state  = require('telescope.actions.state')
  local actions       = require('telescope.actions')
  local pickers       = require('telescope.pickers')
  local finders       = require('telescope.finders')
  local conf          = require('telescope.config').values
  local previewers    = require('telescope.previewers')
  local entry_display = require('telescope.pickers.entry_display')
  opts = opts or {}

  -- displayer：* 标记 / 分支名 / 时间 / commit subject
  -- 标记单独成列，当前分支始终红 *；分支名按类型染色
  local displayer = entry_display.create({
    separator = ' ',
    items = {
      { width = 1 },        -- * 标记
      { width = 40 },       -- branch name
      { width = 15 },       -- MM-DD HH:MM:SS
      { remaining = true }, -- subject
    },
  })

  local function make_display(entry)
    return displayer({
      { entry.is_head and '*' or ' ', 'VVBranchHead' },
      { entry.name,                   entry.branch_hl },
      { entry.time_str,               entry.time_hl },
      { entry.subject },
    })
  end

  local function make_entry(item)
    return {
      value      = item.name,
      ordinal    = item.name,
      name       = item.name,
      is_head    = item.is_head,
      is_remote  = item.is_remote,
      branch_hl  = item.branch_hl,
      time_str   = item.time_str,
      time_hl    = item.time_hl,
      subject    = item.subject,
      display    = make_display,
    }
  end

  local previewer = previewers.new_buffer_previewer({
    title = 'Branch Log',
    define_preview = function(self, entry)
      if self.state.job_id then
        pcall(vim.fn.jobstop, self.state.job_id)
      end
      local bufnr = self.state.bufnr
      local winid = self.state.winid
      local chan = vim.api.nvim_open_term(bufnr, {})
      self.state.job_id = vim.fn.jobstart({
        'bash', '-c',
        'git log --color=always --graph --decorate --oneline '
          .. vim.fn.shellescape(entry.value) .. ' -40',
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

  pickers.new(opts, {
    prompt_title = 'Checkout ↵  New ^A  Delete ^D  Rebase ^R  Merge ^Y  Fetch ⌥F  Copy ⌥Y',
    previewer    = previewer,
    sorter       = conf.generic_sorter(opts),
    finder = finders.new_table({
      results = get_branches(),
      entry_maker = make_entry,
    }),

    attach_mappings = function(prompt_bufnr, map)
      local checktime = function() vim.cmd('checktime') end

      -- CR: checkout。本地直接切；远程自动建本地 tracking branch（避免 detached HEAD）
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        actions.close(prompt_bufnr)

        if not entry.is_remote then
          git_async({ 'git', 'checkout', entry.value }, function(code)
            return code == 0
              and ('Checked out: ' .. entry.value)
              or  ('Checkout failed (exit ' .. code .. ')')
          end, checktime)
          return
        end

        -- 远程：先建 tracking branch；同名本地已存在则退回普通 checkout（首次失败静默兜底）
        local _, branch = parse_remote(entry.value)
        vim.fn.jobstart({ 'git', 'checkout', '-b', branch, '--track', entry.value }, {
          on_exit = function(_, code)
            if code == 0 then
              vim.schedule(function()
                vim.notify('Checked out: ' .. branch .. ' (tracking ' .. entry.value .. ')', vim.log.levels.INFO)
                checktime()
              end)
              return
            end
            vim.fn.jobstart({ 'git', 'checkout', branch }, {
              on_exit = function(_, code2)
                vim.schedule(function()
                  if code2 == 0 then
                    vim.notify('Checked out: ' .. branch, vim.log.levels.INFO)
                    checktime()
                  else
                    vim.notify('Checkout failed: ' .. branch, vim.log.levels.ERROR)
                  end
                end)
              end,
            })
          end,
        })
      end)

      -- C-a: 新建分支。内置 git_create_branch 把搜索过滤行当分支名（不弹输入），自己写
      -- 弹 input 询问新名，以当前选中分支为起点 checkout -b
      map({ 'i', 'n' }, '<C-a>', function()
        local entry = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        vim.ui.input({ prompt = 'New branch name: ' }, function(name)
          if not name or name == '' then return end
          local args = { 'git', 'checkout', '-b', name }
          if entry then args[#args + 1] = entry.value end -- 起点分支
          git_async(args, function(code)
            return code == 0
              and ('Created and checked out: ' .. name)
              or  ('Create failed (exit ' .. code .. ')')
          end, checktime)
        end)
      end)

      -- C-d: 删除。本地 → git branch -D；远程 → git push --delete。均单键 y/n 确认
      map({ 'i', 'n' }, '<C-d>', function()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        actions.close(prompt_bufnr)

        if not entry.is_remote then
          if not confirm('Delete branch ' .. entry.value .. ' ?') then return end
          git_async({ 'git', 'branch', '-D', entry.value }, function(code)
            return code == 0
              and ('Deleted branch: ' .. entry.value)
              or  ('Delete failed (exit ' .. code .. ')')
          end)
          return
        end

        local remote, branch = parse_remote(entry.value)
        if not confirm('Delete remote branch ' .. entry.value .. ' ?') then return end
        git_async({ 'git', 'push', remote, '--delete', branch }, function(code)
          return code == 0
            and ('Deleted remote branch: ' .. entry.value)
            or  ('Delete failed (exit ' .. code .. ')')
        end)
      end)

      -- C-r: rebase（全局 defaults 绑成了 preview scroll，重绑回来）
      map({ 'i', 'n' }, '<C-r>', function()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        actions.close(prompt_bufnr)
        if not confirm('Rebase current branch onto ' .. entry.value .. ' ?') then return end
        git_async({ 'git', 'rebase', entry.value }, function(code)
          return code == 0
            and ('Rebased onto: ' .. entry.value)
            or  ('Rebase failed (exit ' .. code .. ')')
        end, checktime)
      end)

      -- C-y: merge（全局 defaults 绑成了 preview scroll，重绑回来）
      map({ 'i', 'n' }, '<C-y>', function()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        actions.close(prompt_bufnr)
        if not confirm('Merge ' .. entry.value .. ' into current branch ?') then return end
        git_async({ 'git', 'merge', entry.value }, function(code)
          return code == 0
            and ('Merged: ' .. entry.value)
            or  ('Merge failed (exit ' .. code .. ')')
        end, checktime)
      end)

      -- M-f: fetch --all，成功后静默关闭并重开 picker（保留原 opts）
      map({ 'i', 'n' }, '<M-f>', function()
        vim.notify('git fetch --all ...', vim.log.levels.INFO)
        git_async(
          { 'git', 'fetch', '--all' },
          function(code)
            return code ~= 0 and ('Fetch failed (exit ' .. code .. ')') or nil
          end,
          function()
            actions.close(prompt_bufnr)
            M.open(opts)
          end
        )
      end)

      -- M-y: 复制分支名（yank）
      map({ 'i', 'n' }, '<M-y>', function()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        yank(entry.value)
      end)

      return true
    end,
  }):find()
end

return M
