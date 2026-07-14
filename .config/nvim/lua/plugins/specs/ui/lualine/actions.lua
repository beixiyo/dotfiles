-- Lualine 点击交互
local path = require('vv-utils.path')
local editor = require('vv-utils.editor')
local copy = function(text) editor.copy(text, { title = 'Lualine' }) end

local M = {}

-- telescope.builtin 懒加载；失败（未装 telescope）时回退到参数里的 fallback
local function tele_or(builtin_name, fallback)
  return function()
    local ok, tb = pcall(require, 'telescope.builtin')
    if ok and tb[builtin_name] then tb[builtin_name]() else fallback() end
  end
end

M.visual_range = editor.visual_range

function M.copy_datetime()
  copy(os.date('%Y-%m-%d %H:%M:%S'))
end

--- VSCode 风格：弹出输入框 → commit（已暂存的文件）→ push
function M.quick_commit_push()
  local check = vim.system({ 'git', 'diff', '--cached', '--quiet' }):wait()
  if check.code == 0 then
    vim.notify('没有已暂存的文件，请先 git add', vim.log.levels.WARN)
    return
  end

  vim.ui.input({ prompt = 'Commit message: ' }, function(msg)
    if not msg or msg == '' then return end

    vim.system({ 'git', 'commit', '-m', msg }, {}, function(cm)
      if cm.code ~= 0 then
        vim.schedule(function() vim.notify('commit 失败: ' .. (cm.stderr or ''), vim.log.levels.ERROR) end)
        return
      end

      vim.schedule(function() vim.notify('已提交: ' .. msg, vim.log.levels.INFO) end)
      vim.system({ 'git', 'push' }, {}, function(ps)
        vim.schedule(function()
          if ps.code == 0 then
            vim.notify('已推送到远程', vim.log.levels.INFO)
          else
            vim.notify('push 失败: ' .. (ps.stderr or ''), vim.log.levels.WARN)
          end
        end)
      end)
    end)
  end)
end

M.open_branch_view = tele_or('git_branches', function() vim.notify('telescope 未加载', vim.log.levels.WARN) end)
M.open_git_status  = tele_or('git_status',   function() vim.notify('telescope 未加载', vim.log.levels.WARN) end)

function M.open_git_log()
  local ok, git_log = pcall(require, 'plugins.specs.ui.telescope.git_log')
  if ok then
    git_log.open()
  else
    vim.notify('telescope git_log 未加载', vim.log.levels.WARN)
  end
end

function M.copy_abs_path()
  editor.copy_path({ title = 'Lualine' })
end

function M.copy_abs_path_line()
  editor.copy_path({ line = true, title = 'Lualine' })
end

function M.next_diagnostic()
  vim.diagnostic.goto_next()
end

function M.blame_line()
  if package.loaded['gitsigns'] then
    require('gitsigns').blame_line({ full = true })
  else
    pcall(vim.cmd, 'Git blame')
  end
end

function M.open_mason()
  if vim.fn.exists(':Mason') == 2 then vim.cmd('Mason') end
end

function M.go_top()
  vim.cmd('normal! gg')
end

function M.open_root_picker()
  local ok, tb = pcall(require, 'telescope.builtin')
  if ok and tb.find_files then
    tb.find_files({ cwd = path.get_root() })
  else
    vim.cmd('edit ' .. (path.get_root() or '.'))
  end
end

-- 优先 Trouble，否则用内置 quickfix
function M.open_diagnostics()
  if pcall(require, 'trouble') then
    vim.cmd('Trouble diagnostics toggle')
  else
    vim.diagnostic.setqflist()
  end
end

-- 老版无 :LspInfo 时用 checkhealth 兜底
function M.open_lsp_info()
  if vim.fn.exists(':LspInfo') == 2 then
    vim.cmd('LspInfo')
  else
    vim.cmd('checkhealth vim.lsp')
  end
end

function M.toggle_dap_repl()
  local ok, dap = pcall(require, 'dap')
  if ok then dap.repl.toggle() end
end

function M.center_line()
  vim.cmd('normal! zz')
end

return M
