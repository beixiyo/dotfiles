-- 分支管理 picker：本地+远程统一显示，时间排序+分级高亮
-- 本地分支在上，远程分支在下，各自按 committerdate 降序
-- 全局 defaults 把 C-d/C-r/C-y 绑成了 preview scroll，attach_mappings 里显式重绑回来
-- 所有 git 操作走 shared.git_async（exit code 唯一成败信号，stderr 并入失败通知）
-- C-a 新建分支：vim.ui.input 弹名字，以选中分支为起点 checkout -b
-- CR checkout 远程分支时自动建本地 tracking branch（避免 detached HEAD）
--   同名本地分支已存在时退回普通 checkout，随后 --ff-only 同步到选中远端（diverged 仅提示）
-- 删除/合并/rebase 用 vim.fn.confirm 单键 y/n 确认（参照 vv-explorer，无需回车）
-- C-d 支持 Tab 多选批量删除：当前分支跳过，本地合并一条命令，远程按 remote 分组
-- 批量删除是部分成功语义，失败组事后校验仍存在的分支：点名通知并 refresh 校准列表
-- M-y 多选时空格拼接复制；数据与展示映射见 data.lua，previewer 见 shared.term_previewer
-- 批量删除的分组与事后校验见 delete.lua（纯/异步函数，tests/telescope/ 直测）
local M = {}
local Git   = require('plugins.specs.ui.telescope.git.shared')
local Data  = require('plugins.specs.ui.telescope.git.branches.data')
local Delete = require('plugins.specs.ui.telescope.git.branches.delete')
local Keys  = require('vv-utils.keys')

-- 单键 y/n 确认（默认 No），参照 vv-explorer 删除弹窗
local function confirm(question)
  return vim.fn.confirm(question, '&Yes\n&No', 2) == 1
end

function M.open(opts)
  Data.ensure_hl()

  local action_state  = require('telescope.actions.state')
  local actions       = require('telescope.actions')
  local pickers       = require('telescope.pickers')
  local finders       = require('telescope.finders')
  local conf          = require('telescope.config').values
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

  local function new_finder()
    return finders.new_table({
      results = Data.get_branches(),
      entry_maker = make_entry,
    })
  end

  local previewer = Git.term_previewer('Branch Log', function(entry)
    return {
      'bash', '-c',
      'git log --color=always --graph --decorate --oneline '
        .. vim.fn.shellescape(entry.value) .. ' -40',
    }
  end)

  pickers.new(opts, {
    prompt_title = table.concat({
      Keys.hint('Checkout', '<CR>'),
      Keys.hint('New', '<C-a>'),
      Keys.hint('Delete', '<C-d>'),
      Keys.hint('Rebase', '<C-r>'),
      Keys.hint('Merge', '<C-y>'),
      Keys.hint('Fetch', '<M-f>'),
      Keys.hint('Cp', '<M-y>'),
    }, '  '),
    previewer    = previewer,
    sorter       = conf.generic_sorter(opts),
    finder = new_finder(),

    attach_mappings = function(prompt_bufnr, map)
      local checktime = function() vim.cmd('checktime') end
      local refresh_branches = function()
        local ok, picker = pcall(action_state.get_current_picker, prompt_bufnr)
        if not ok or not picker then return end
        picker:refresh(new_finder(), { reset_prompt = false })
      end

      local checktime_and_refresh = function()
        checktime()
        refresh_branches()
      end

      -- CR: checkout。本地直接切；远程自动建本地 tracking branch（避免 detached HEAD）
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        actions.close(prompt_bufnr)

        if not entry.is_remote then
          Git.git_async({ 'git', 'checkout', entry.value }, function(code)
            return code == 0
              and ('Checked out: ' .. entry.value)
              or  ('Checkout failed (exit ' .. code .. ')')
          end, checktime)
          return
        end

        -- 远程：先建 tracking branch；同名本地已存在则退回普通 checkout
        -- fetch 只更新远端追踪 ref，旧本地分支会停留在上次 checkout 的位置
        -- 故 checkout 后追加 --ff-only 同步：可 ff 则前进到选中远端，diverged 安全失败仅提示
        local _, branch = Data.parse_remote(entry.value)
        if not branch then return end
        vim.fn.jobstart({ 'git', 'checkout', '-b', branch, '--track', entry.value }, {
          on_exit = function(_, code)
            if code == 0 then
              vim.schedule(function()
                vim.notify('Checked out: ' .. branch .. ' (tracking ' .. entry.value .. ')', vim.log.levels.INFO)
                checktime()
              end)
              return
            end
            Git.git_async({ 'git', 'checkout', branch }, function(code2)
              if code2 ~= 0 then return 'Checkout failed: ' .. branch end
            end, function()
              Git.git_async({ 'git', 'merge', '--ff-only', entry.value }, function(code3)
                if code3 == 0 then
                  return 'Checked out: ' .. branch .. ' (synced to ' .. entry.value .. ')'
                end
                return 'Checked out: ' .. branch .. ', cannot fast-forward to ' .. entry.value .. ', manual sync needed'
              end, nil, checktime)
            end)
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
          Git.git_async(args, function(code)
            return code == 0
              and ('Created and checked out: ' .. name)
              or  ('Create failed (exit ' .. code .. ')')
          end, checktime)
        end)
      end)

      -- C-d: 删除。本地 → git branch -D；远程 → git push --delete。均单键 y/n 确认
      -- Tab 多选后批量删；无多选时按当前行处理，保持单条确认文案
      -- 多选契约：多选非空时只删被勾选的 entry，光标行不自动纳入
      --（get_multi_selection 不含未勾选行；delete_selection 的光标 fallback 仅在多选为空时触发）
      map({ 'i', 'n' }, '<C-d>', function()
        local picker = action_state.get_current_picker(prompt_bufnr)
        local entries = picker and picker:get_multi_selection() or {}
        if #entries == 0 then
          entries = { action_state.get_selected_entry() }
        end
        if not entries[1] then return end

        if #entries == 1 then
          local entry = entries[1]

          if entry.is_head then
            vim.notify('Cannot delete current branch', vim.log.levels.WARN)
            return
          end

          if not entry.is_remote then
            if not confirm('Delete branch ' .. entry.value .. ' ?') then return end
            Git.git_async({ 'git', 'branch', '-D', entry.value }, function(code)
              return code == 0
                and ('Deleted branch: ' .. entry.value)
                or  ('Delete failed: ' .. entry.value .. ' (exit ' .. code .. ')')
            end, refresh_branches)
            return
          end

          local remote, branch = Data.parse_remote(entry.value)
          if not confirm('Delete remote branch ' .. entry.value .. ' ?') then return end
          Git.git_async({ 'git', 'push', remote, '--delete', branch }, function(code)
            return code == 0
              and ('Deleted remote branch: ' .. entry.value)
              or  ('Delete failed: ' .. entry.value .. ' (exit ' .. code .. ')')
          end, refresh_branches)
          return
        end

        -- 批量：分组（is_head 跳过、本地/远程分流）在 delete.lua；此处只做确认与 UI
        local grouped = Delete.group(entries)
        local locals, by_remote, skipped = grouped.locals, grouped.by_remote, grouped.skipped

        local remote_cnt = 0
        for _, list in pairs(by_remote) do remote_cnt = remote_cnt + #list end
        if #locals == 0 and remote_cnt == 0 then
          vim.notify('Nothing to delete (current branch skipped)', vim.log.levels.WARN)
          return
        end

        local parts = {}
        if #locals > 0    then parts[#parts + 1] = #locals .. ' local' end
        if remote_cnt > 0 then parts[#parts + 1] = remote_cnt .. ' remote' end
        local suffix = skipped > 0 and ' (skip current branch)' or ''
        if not confirm('Delete ' .. table.concat(parts, ' + ') .. ' branches' .. suffix .. ' ?') then return end

        -- 乐观移除选中行并清空多选（delete_buffer 同款 API）
        -- predicate 排除 is_head：被跳过的当前分支行保留在列表
        -- 批量删除是部分成功语义：git 逐条尝试，失败组事后校验仍存在的分支并 refresh 校准
        if picker then picker:delete_selection(function(sel) return not sel.is_head end) end

        -- 事后校验（delete.existing）：仍存在的分支 = 删除失败者，点名通知并 refresh
        local function verify_and_refresh(kind, remote, names)
          Delete.existing(kind, remote, function(existing)
            if existing == nil then
              vim.notify('Verify failed', vim.log.levels.ERROR)
            else
              local set = {}
              for _, n in ipairs(existing) do set[n] = true end
              local failed = {}
              for _, n in ipairs(names) do
                if set[n] then failed[#failed + 1] = n end
              end
              if #failed > 0 then
                vim.notify('Delete failed: ' .. table.concat(failed, ', '), vim.log.levels.ERROR)
              end
            end
            refresh_branches()
          end)
        end

        if #locals > 0 then
          local args = { 'git', 'branch', '-D' }
          for _, name in ipairs(locals) do args[#args + 1] = name end
          Git.git_async(args, function(code)
            if code == 0 then return 'Deleted ' .. #locals .. ' branches' end
          end, refresh_branches, function(code)
            if code ~= 0 then verify_and_refresh('local', nil, locals) end
          end)
        end
        for remote, list in pairs(by_remote) do
          local args = { 'git', 'push', remote, '--delete' }
          for _, name in ipairs(list) do args[#args + 1] = name end
          Git.git_async(args, function(code)
            if code == 0 then return 'Deleted ' .. #list .. ' remote branches (' .. remote .. ')' end
          end, refresh_branches, function(code)
            if code ~= 0 then verify_and_refresh('remote', remote, list) end
          end)
        end
      end)

      -- C-r: rebase（全局 defaults 绑成了 preview scroll，重绑回来）
      map({ 'i', 'n' }, '<C-r>', function()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        if not confirm('Rebase current branch onto ' .. entry.value .. ' ?') then return end
        Git.git_async({ 'git', 'rebase', entry.value }, function(code)
          return code == 0
            and ('Rebased onto: ' .. entry.value)
            or  ('Rebase failed (exit ' .. code .. ')')
        end, checktime_and_refresh)
      end)

      -- C-y: merge（全局 defaults 绑成了 preview scroll，重绑回来）
      map({ 'i', 'n' }, '<C-y>', function()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        if not confirm('Merge ' .. entry.value .. ' into current branch ?') then return end
        Git.git_async({ 'git', 'merge', entry.value }, function(code)
          return code == 0
            and ('Merged: ' .. entry.value)
            or  ('Merge failed (exit ' .. code .. ')')
        end, checktime_and_refresh)
      end)

      -- M-f: fetch --all，成功后原地刷新（保留搜索词；picker 已关则静默跳过，不重建 UI）
      map({ 'i', 'n' }, '<M-f>', function()
        vim.notify('git fetch --all ...', vim.log.levels.INFO)
        Git.git_async(
          { 'git', 'fetch', '--all' },
          function(code)
            return code ~= 0 and ('Fetch failed (exit ' .. code .. ')') or nil
          end,
          refresh_branches
        )
      end)

      -- M-y: 复制分支名（yank）；多选时空格拼接
      map({ 'i', 'n' }, '<M-y>', function()
        local picker = action_state.get_current_picker(prompt_bufnr)
        local entries = picker and picker:get_multi_selection() or {}
        if #entries == 0 then
          entries = { action_state.get_selected_entry() }
        end
        if not entries[1] then return end

        if #entries == 1 then
          Git.yank(entries[1].value, 'branch')
          return
        end

        local names = {}
        for _, e in ipairs(entries) do names[#names + 1] = e.value end
        local text = table.concat(names, ' ')
        vim.fn.setreg('+', text)
        vim.fn.setreg('"', text)
        vim.notify('Copied ' .. #names .. ' branch names', vim.log.levels.INFO)
      end)

      return true
    end,
  }):find()
end

return M
