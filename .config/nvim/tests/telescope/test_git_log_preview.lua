-- git log 预览的统计头与截断契约：terminal buffer scrollback 默认 10000 行，
-- 超大 commit 的 delta 输出会把头部统计行顶出 buffer（只剩 diff 尾部）
-- 这里用真实 git 仓库 + 真实 delta pipeline 验证：截断后统计头保住、
-- 底部出现截断提示；普通 commit 完整渲染且统计头数字正确。无 delta 的机器跳过
-- 注意：child.lua_func 走 string.dump 不传 upvalue，公共逻辑经 SETUP_SRC 注入 _G
local H = dofile('tests/helpers.lua')
local MiniTest = require('mini.test')
local T, child = H.new_set()

-- 注入 child 的公共部分：stub telescope 构造边界、提交 fixture、调用 define_preview
-- setup_log_previewer 必须在 with_git_repo 内调用（git_root 在 M.open 闭包内捕获）
local SETUP_SRC = [==[
_G.setup_log_previewer = function()
  local define_preview
  package.loaded['telescope.previewers'] = {
    new_buffer_previewer = function(opts)
      define_preview = opts.define_preview
      return opts
    end,
  }
  package.loaded['telescope.builtin'] = {
    git_commits = function() end,
  }
  package.loaded['telescope.actions'] = {
    select_default = { replace = function() end },
  }
  package.loaded['telescope.actions.state'] = {}
  require('plugins.specs.ui.telescope.git.log').open({ cwd = vim.fn.getcwd() })
  check(define_preview ~= nil, 'git log 必须为 delta 预览构造 define_preview')
  _G.__log_define_preview = define_preview
end

_G.commit_files = function(repo, files, message)
  for name, content in pairs(files) do
    local file = assert(io.open(repo.dir .. '/' .. name, 'wb'))
    file:write(content)
    file:close()
  end
  local _, code = _G.H.git(repo.dir, 'add', '-A')
  check(code == 0, '暂存失败')
  _, code = _G.H.git(repo.dir, 'commit', '-q', '-m', message)
  check(code == 0, '提交失败')
  return vim.trim(vim.fn.system('git -C ' .. vim.fn.shellescape(repo.dir) .. ' rev-parse HEAD'))
end

_G.numbered_lines = function(n)
  local lines = {}
  for i = 1, n do
    lines[i] = 'line-' .. i
  end
  return table.concat(lines, '\n') .. '\n'
end

-- 模拟 telescope：每个 entry 新建 preview buffer 并调用 define_preview
_G.run_preview = function(hash)
  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  _G.__log_define_preview({ state = { bufnr = buf, winid = win } }, { value = hash })
  return buf
end

_G.tail_text = function(buf, n)
  return table.concat(vim.api.nvim_buf_get_lines(buf, -n - 1, -1, false), '\n')
end
]==]

local function require_delta()
  if vim.fn.executable('delta') == 0 then
    MiniTest.skip('本机缺少 delta，git log 预览不启用')
  end
end

T['超大 commit 预览截断后统计头仍在第 1 行'] = function()
  require_delta()
  child.lua(SETUP_SRC)
  child.lua_func(function()
    local H = _G.H
    H.with_git_repo(function(repo)
      _G.setup_log_previewer()

      -- 11000 行改动超过 scrollback（10000）：不截断时统计头会被顶出 buffer
      local buf = _G.run_preview(_G.commit_files(repo, { big = _G.numbered_lines(11000) }, 'big'))

      -- 截断提示与 diff 同一次写入，出现即代表渲染落地
      wait(function()
        return _G.tail_text(buf, 3):find('truncated', 1, true) ~= nil
      end, 20000, '超大 commit 预览未在限时内出现截断提示')

      local all = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      check(all[1]:find('Commit changes  +11000  -0', 1, true) ~= nil,
        '统计头必须保留在第 1 行且统计完整 commit：实际是 ' .. all[1])
      check(_G.tail_text(buf, 3):find('press <CR> for the full commit view', 1, true) ~= nil,
        '截断提示必须告知查看完整 commit 的入口')
      check(#all < 10000, '预览行数必须低于 scrollback 上限，实际 ' .. #all)
    end)
  end)
end

T['普通 commit 预览完整且统计头计入 binary'] = function()
  require_delta()
  child.lua(SETUP_SRC)
  child.lua_func(function()
    local H = _G.H
    H.with_git_repo(function(repo)
      _G.setup_log_previewer()

      local buf = _G.run_preview(_G.commit_files(repo, {
        small = _G.numbered_lines(50),
        blob = '\0\1\2',
      }, 'small'))

      wait(function()
        return _G.tail_text(buf, 5):find('line%-50') ~= nil
      end, 10000, '普通 commit 预览未在限时内渲染到最后一行')

      local all = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      eq(all[1], 'Commit changes  +50  -0  ·  50 lines  ·  1 binary',
        '统计头必须汇总文本增删并单独计数 binary 文件')
      check(table.concat(all, '\n'):find('truncated', 1, true) == nil,
        '未达上限的预览不得出现截断提示')
    end)
  end)
end

return T
