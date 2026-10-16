-- 当前 buffer 的 git commit 历史 + delta 预览，选中后 diff 对比
local M = {}
local Git = require('plugins.specs.ui.telescope.git.shared')
local Keys = require('vv-utils.keys')

local function make_delta_previewer()
  if vim.fn.executable('delta') == 0 then return nil end

  return Git.term_previewer('Git Buffer Log', function(entry, winid)
    return {
      'bash', '-c',
      'git show --color=always "$1" | delta --side-by-side --width="$2"',
      '_', entry.value, tostring(vim.api.nvim_win_get_width(winid)),
    }
  end)
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

      local vvgit = Git.load_vv_git()
      if not vvgit or type(vvgit.compare_file) ~= 'function' then
        vim.notify('vv-git does not support compare_file', vim.log.levels.ERROR)
        return
      end

      actions.close(prompt_bufnr)
      local resumed = false
      local function resume()
        if resumed then return end
        resumed = true
        require('telescope.builtin').resume()
      end
      vvgit.compare_file(entry.value, {
        bufnr = source_buf,
        on_close = resume,
        on_error = resume,
      })
    end)

    -- 复制 commit hash（留在 telescope）
    map({ 'i', 'n' }, '<M-h>', function(prompt_bufnr)
      local entry = action_state.get_selected_entry(prompt_bufnr)
      if not entry then return end
      Git.yank(entry.value, 'hash')
    end)

    -- 复制 commit 标题（留在 telescope）
    map({ 'i', 'n' }, '<M-y>', function(prompt_bufnr)
      local entry = action_state.get_selected_entry(prompt_bufnr)
      if not entry then return end
      Git.yank(Git.commit_subject(entry.value), 'message')
    end)

    -- 在普通 buffer 中打开 diff（可 visual 选区复制，q/<Esc> 关闭并回到 telescope）
    map({ 'i', 'n' }, '<C-o>', function(prompt_bufnr)
      local entry = action_state.get_selected_entry(prompt_bufnr)
      if not entry then return end
      actions.close(prompt_bufnr)
      Git.open_show_buffer(entry.value, function() require('telescope.builtin').resume() end)
    end)

    return true
  end

  opts.layout_config = { preview_width = 0.75 }
  opts.prompt_title = table.concat({
    Keys.hint('Diff', '<CR>'),
    Keys.hint('RawDiff', '<C-o>'),
    Keys.hint('Hash', '<M-h>'),
    Keys.hint('Msg', '<M-y>'),
  }, '  ')
  require('telescope.builtin').git_bcommits(opts)
end

return M
