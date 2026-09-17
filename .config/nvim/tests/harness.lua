-- tests/harness.lua — 共享测试基建：断言、git fixture、notify 捕获、异步等待
-- 测试文件样板（任意层级子目录均可定位）：
--   local this = debug.getinfo(1, 'S').source:sub(2)
--   local H = dofile(vim.fs.find('harness.lua', { upward = true, path = vim.fs.dirname(this) })[1])
local M = {}

M.root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')

-- 生产模块（lua/ 下）可 require 的前提：配置根进 rtp
vim.opt.runtimepath:prepend(M.root)

-- 追加 runtimepath（如 vendors 插件），相对 M.root
function M.rtp(...)
  for _, rel in ipairs({ ... }) do
    vim.opt.runtimepath:prepend(M.root .. '/' .. rel)
  end
end

-- ── 断言 ─────────────────────────────────────────────────────────────────────

-- 失败消息应描述被破坏的契约，而非复述断言本身
function M.check(cond, msg)
  if not cond then error(msg, 0) end
end

function M.eq(actual, expected, msg)
  if not vim.deep_equal(actual, expected) then
    error(('%s\n  expected: %s\n  actual:   %s')
      :format(msg, vim.inspect(expected), vim.inspect(actual)), 0)
  end
end

-- ── git fixture ──────────────────────────────────────────────────────────────

-- 在 dir 内执行 git，返回 (stdout 行列表, exit code)
function M.git(dir, ...)
  local out = vim.fn.systemlist({ 'git', '-C', dir, ... })
  return out, vim.v.shell_error
end

--- 临时 git 仓库 fixture：fn(repo) 结束（含失败）后整棵删除，幂等可重复跑
--- fn 执行期间 cwd 切到 repo（适配不带 -C 的生产代码，如 git_async / ls-remote 查询）
--- opts.remote = true 时附带 bare origin 并 push main
---@param opts table?  { remote = boolean }
---@param fn function fun(repo: { dir: string, remote: string?, base: string })
function M.with_git_repo(opts, fn)
  if type(opts) == 'function' then opts, fn = {}, opts end
  opts = opts or {}

  local base = vim.fn.tempname()
  vim.fn.mkdir(base, 'p')
  local repo = { dir = base .. '/repo', base = base }
  vim.fn.mkdir(repo.dir, 'p')

  -- fixture 关键步骤失败立即报错（否则后续失败难定位）
  local function must_git(dir, ...)
    local _, code = M.git(dir, ...)
    if code ~= 0 then
      error(('fixture git failed (exit %s): git -C %s %s'):format(code, dir, table.concat({ ... }, ' ')), 0)
    end
  end

  must_git(repo.dir, 'init', '-q', '-b', 'main')
  must_git(repo.dir, 'config', 'user.email', 'test@local')
  must_git(repo.dir, 'config', 'user.name', 'test')
  must_git(repo.dir, 'commit', '-q', '--allow-empty', '-m', 'init')

  if opts.remote then
    repo.remote = base .. '/remote.git'
    vim.fn.mkdir(repo.remote, 'p')
    must_git(repo.remote, 'init', '-q', '--bare', '-b', 'main')
    must_git(repo.dir, 'remote', 'add', 'origin', repo.remote)
    must_git(repo.dir, 'push', '-q', '-u', 'origin', 'main')
  end

  local old_cwd = vim.fn.getcwd()
  vim.cmd('cd ' .. vim.fn.fnameescape(repo.dir))
  local ok, err = pcall(fn, repo)
  vim.cmd('cd ' .. vim.fn.fnameescape(old_cwd))

  vim.fn.delete(base, 'rf')
  if not ok then error(err, 0) end
end

-- ── 异步与通知 ───────────────────────────────────────────────────────────────

--- 等待条件成立，超时报错（条件等待优于固定 sleep，时序不赌运气）
function M.wait(cond, timeout, msg)
  if not vim.wait(timeout or 5000, cond, 50) then
    error(msg or 'timeout waiting for condition', 0)
  end
end

--- 捕获 fn 执行期间的 vim.notify 调用（fn 内需自行 wait 到异步通知落地后返回）
--- 返回 { { msg = string, level = number } }
function M.capture_notify(fn)
  local saved = vim.notify
  local events = {}
  vim.notify = function(msg, level)
    events[#events + 1] = { msg = msg, level = level }
  end
  local ok, err = pcall(fn)
  vim.notify = saved
  if not ok then error(err, 0) end
  return events
end

return M
