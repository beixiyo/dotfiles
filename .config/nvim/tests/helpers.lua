-- 根目录配置测试共享基建，接入 vv-utils 共享 mini.test 入口（tests/run.sh 启动）
-- 父进程纯数据用例：H.eq / H.check / H.wait / H.capture_notify / H.git / H.with_git_repo
-- 需要模块、窗口或异步状态隔离的用例：local T, child = H.new_set({ 依赖环境变量名 })
-- 每个 case 独立 child Neovim（-u NONE），cwd / HOME / XDG / 临时文件根在本 case 的独立 fixture；
-- child 内提供全局 H / eq / check / wait，异步异常由父 hook 兜底断言
local M = {}

-- ── 父进程断言与 fixture（纯数据用例） ───────────────────────────────────────

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

  local old_cwd = vim.fn.getcwd()
  -- 初始化也属于 fixture 生命周期，git 失败时同样归还 cwd 并删除临时目录
  local ok, err = xpcall(function()
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

    vim.cmd('cd ' .. vim.fn.fnameescape(repo.dir))
    fn(repo)
  end, debug.traceback)
  local restored, restore_err = pcall(vim.cmd, 'cd ' .. vim.fn.fnameescape(old_cwd))
  local cleaned = vim.fn.delete(base, 'rf') == 0
  if not ok then error(err, 0) end
  assert(restored, restore_err)
  assert(cleaned, '清理 Git fixture 失败：' .. base)
end

-- ── 独立 child 的具名集合 ────────────────────────────────────────────────────

-- 在 child 内安装隔离环境、runtimepath 与断言工具；依赖目录按声明逐个校验并前置
local function boot_child(child, deps)
  child.lua([[
    local root = assert(vim.env.VV_TEST_TMP, '临时根目录不能为空')
    assert(root ~= '' and vim.fn.isdirectory(root) == 1, '临时根目录必须存在')
    assert(vim.uv.fs_realpath(vim.fn.getcwd()) == vim.uv.fs_realpath(root), '子进程 cwd 必须在本场景 fixture')
    for _, key in ipairs({ 'HOME', 'TMPDIR', 'XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_STATE_HOME', 'XDG_CACHE_HOME' }) do
      local path = vim.env[key]
      assert(type(path) == 'string' and path:sub(1, #root + 1) == root .. '/', '环境路径未隔离：' .. key)
    end
    for _, kind in ipairs({ 'config', 'data', 'state', 'cache' }) do
      assert(vim.fn.stdpath(kind):sub(1, #root + 1) == root .. '/', '持久目录未隔离：' .. kind)
    end
    assert(type(vim.env.VV_TEST_REPO) == 'string' and vim.env.VV_TEST_REPO ~= '', '被测配置根路径不能为空')
    assert(type(vim.env.VV_UTILS) == 'string' and vim.env.VV_UTILS ~= '', '共享工具路径不能为空')
    assert(vim.fn.isdirectory(vim.env.VV_TEST_REPO) == 1, '被测配置根路径必须存在')
    assert(vim.fn.isdirectory(vim.env.VV_UTILS) == 1, '共享工具路径必须存在')
    -- 即使调用方提供 pack 根目录，也不自动加载个人 package
    vim.opt.packpath = ''
    dofile(vim.env.VV_UTILS .. '/dev/test/runtime.lua').apply()
    vim.opt.runtimepath:prepend(vim.env.VV_TEST_REPO)
    vim.opt.runtimepath:prepend(vim.env.VV_UTILS)
  ]] .. (#deps > 0 and ([[
    for _, name in ipairs({ ']] .. table.concat(deps, "', '") .. [[' }) do
      local path = assert(vim.env[name], name .. ' 未声明：检查 tests/env.sh')
      assert(path ~= '' and vim.fn.isdirectory(path) == 1, name .. ' 必须是存在目录: ' .. path)
      vim.opt.runtimepath:prepend(path)
    end
  ]]) or '') .. [[
    vim.env.GIT_CONFIG_GLOBAL, vim.env.GIT_CONFIG_SYSTEM = '/dev/null', '/dev/null'
    vim.env.GIT_INDEX_FILE, vim.env.GIT_DIR, vim.env.GIT_WORK_TREE = nil, nil, nil
    vim.env.GIT_CONFIG_COUNT = nil
    local counter = 0
    vim.fn.tempname = function()
      counter = counter + 1
      return vim.env.VV_TEST_TMP .. '/fixture-' .. counter
    end
    async_errors = {}
    local schedule = vim.schedule
    -- 异步异常留到父 hook 断言，不能被回调边界静默吞掉
    vim.schedule = function(callback)
      schedule(function()
        local ok, err = xpcall(callback, debug.traceback)
        if not ok then async_errors[#async_errors + 1] = tostring(err) end
      end)
    end
    vim.v.errmsg = ''

    -- child 复用相同断言与 Git fixture，不维护第二份实现
    _G.H = dofile(vim.env.VV_TEST_REPO .. '/tests/helpers.lua')
    _G.eq, _G.check, _G.wait = H.eq, H.check, H.wait
  ]])
end

---@param deps string[] 需要挂到 child runtimepath 的插件目录环境变量名（tests/env.sh 声明）
---@return table T mini.test 具名集合
---@return table child mini.test child Neovim
function M.new_set(deps)
  deps = deps or {}
  local MiniTest = require('mini.test')
  local Processes = dofile(assert(vim.env.VV_UTILS, 'VV_UTILS 未设置：请经 tests/run.sh 启动')
    .. '/dev/test/process.lua')
  local child = MiniTest.new_child_neovim()
  local root, pid
  local T = MiniTest.new_set({
    hooks = {
      pre_case = function()
        pid = nil
        for _, name in ipairs(deps) do
          local path = assert(vim.env[name], name .. ' 未声明：检查 tests/env.sh')
          assert(path ~= '' and vim.fn.isdirectory(path) == 1, name .. ' 必须是存在目录: ' .. path)
        end
        -- case 留在共享 scratch 内，信号中断时也能清理；短名称避免 RPC socket 超长
        root = assert(vim.uv.fs_mkdtemp(assert(vim.env.TMPDIR) .. '/cXXXXXX'))
        -- 所有场景使用规范路径，避免 /var 与 /private/var 别名破坏真实路径契约
        root = assert(vim.uv.fs_realpath(root))
        local environment = {
          HOME = root .. '/home', TMPDIR = root .. '/tmp', VV_TEST_TMP = root,
          XDG_CONFIG_HOME = root .. '/config', XDG_DATA_HOME = root .. '/data',
          XDG_STATE_HOME = root .. '/state', XDG_CACHE_HOME = root .. '/cache',
          XDG_RUNTIME_DIR = root .. '/runtime',
        }
        local previous = {}
        for key, value in pairs(environment) do
          assert(type(value) == 'string' and value ~= '', '隔离环境路径不能为空：' .. key)
          vim.fn.mkdir(value, 'p')
          previous[key], vim.env[key] = vim.env[key], value
        end
        -- RPC socket 与启动期环境属于本 case；失败连接也必须归还父环境
        local tempname = vim.fn.tempname
        vim.fn.tempname = function()
          return root .. '/child.sock'
        end
        local started, start_err = pcall(child.start, {
          '-u', 'NONE', '-i', 'NONE', '-n', '--cmd', 'cd ' .. vim.fn.fnameescape(root),
        }, { nvim_executable = vim.v.progpath })
        vim.fn.tempname = tempname
        for key in pairs(environment) do
          vim.env[key] = previous[key]
        end
        if child.job then
          pid = vim.fn.jobpid(child.job.id)
        end
        assert(started, '启动隔离子进程失败：' .. tostring(start_err))
        boot_child(child, deps)
      end,
      post_case = function()
        -- 取证失败不能绕过进程停止与目录删除；不调用可能已被测试替换的生产接口
        local ok, err = pcall(function()
          local errors = child.lua_get([[(function()
            local errors = vim.deepcopy(async_errors)
            if vim.v.errmsg ~= '' then errors[#errors + 1] = vim.v.errmsg end
            return errors
          end)()]])
          assert(#errors == 0, '子进程出现未预期的异步错误：' .. vim.inspect(errors))
        end)
        local descendants_ok, descendants_err = pcall(Processes.stop_descendants, pid)
        local stopped, stop_err = pcall(child.stop)
        pid = nil
        local cleaned = not root or vim.fn.delete(root, 'rf') == 0
        root = nil
        assert(cleaned, '清理场景 fixture 失败')
        assert(stopped, '停止子进程失败：' .. tostring(stop_err))
        assert(descendants_ok, '清理子进程后代失败：' .. tostring(descendants_err))
        assert(ok, err)
      end,
    },
  })
  return T, child
end

return M
