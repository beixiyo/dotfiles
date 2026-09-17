-- stash 管理：apply / pop / drop + delta diff 预览
-- stash push：push_all / push_staged / push_message
local M = {}
local Git = require('plugins.specs.ui.telescope.git.shared')
local Keys = require('vv-utils.keys')

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

--- 暂存所有非忽略变更（index + working tree + untracked）
function M.push_all()
  do_push({ '--include-untracked' }, 'Stash created with all changes')
end

--- 只暂存 index（staged）区域，working tree 不动
function M.push_staged()
  do_push({ '--staged' }, 'Stash created from staged changes')
end

--- 弹出输入框，以自定义消息暂存所有非忽略变更
function M.push_message()
  vim.ui.input({ prompt = 'Stash message: ' }, function(msg)
    if msg == nil then return end -- 按 Esc 取消
    local args = { '--include-untracked' }
    if msg ~= '' then vim.list_extend(args, { '-m', msg }) end
    do_push(args, 'Stash created: ' .. (msg ~= '' and ('"' .. msg .. '"') or '(no message)'))
  end)
end

function M.open(opts)
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')
  opts = opts or {}

  local has_delta = vim.fn.executable('delta') == 1

  opts.previewer = Git.term_previewer('Stash Diff', function(entry, winid)
    local width = vim.api.nvim_win_get_width(winid)
    local cmd = 'git stash show -p --color=always ' .. vim.fn.shellescape(entry.value)
    if has_delta then
      cmd = cmd .. ' | delta --side-by-side --width=' .. width
    end
    return { 'bash', '-c', cmd }
  end)

  opts.layout_config = { preview_width = 0.65 }
  opts.prompt_title = table.concat({
    Keys.hint('Apply', '<CR>'),
    Keys.hint('Pop', '<C-x>'),
    Keys.hint('Drop', '<C-d>'),
  }, '  ')

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
      Git.yank(entry.value, 'stash ref')
    end)

    return true
  end

  require('telescope.builtin').git_stash(opts)
end

return M
