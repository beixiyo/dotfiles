-- 删除分组安全边界，以及真实 worktree 拒删后的事后点名；逐 case 隔离异步 job
local H = dofile('tests/helpers.lua')
local T, child = H.new_set()

T['分组保留本地斜杠、按远程剥前缀并跳过当前分支'] = function()
  child.lua_func(function()
    local Delete = require('plugins.specs.ui.telescope.git.branches.delete')
    local grouped = Delete.group({
      { value = 'main',          is_head = true,  is_remote = false },
      { value = 'dev',           is_head = false, is_remote = false },
      { value = 'feat/login',    is_head = false, is_remote = false },
      { value = 'origin/feat/r', is_head = false, is_remote = true },
      { value = 'up/a/b',        is_head = false, is_remote = true },
      { value = 'bad',           is_head = false, is_remote = true },
    })
    eq(grouped, {
      locals = { 'dev', 'feat/login' }, by_remote = { origin = { 'feat/r' }, up = { 'a/b' } }, skipped = 1,
    }, '删除分组不得误删当前分支、把本地斜杠分支当远程或截断远程多级分支名')
  end)
end

T['事后点名被拒删分支且不误报已删者'] = function()
  child.lua_func(function()
    local H = _G.H
    local Delete = require('plugins.specs.ui.telescope.git.branches.delete')
    H.with_git_repo({ remote = true }, function(repo)
      local function must_git(...)
        local out, code = H.git(repo.dir, ...)
        eq(code, 0, '建立删除 fixture 失败：' .. table.concat(out, '\n'))
      end
      must_git('branch', 'keep-me')
      must_git('branch', 'wt-branch')
      must_git('worktree', 'add', '-q', repo.base .. '/wt', 'wt-branch')
      must_git('push', '-q', 'origin', 'main:refs/heads/r-del')

      local _, code = H.git(repo.dir, 'branch', '-D', 'keep-me', 'wt-branch')
      check(code ~= 0, '删除含被占用分支时必须部分失败')

      local local_left
      Delete.existing('local', nil, function(names) local_left = names end)
      wait(function() return local_left ~= nil end, 5000, '本地查询未回调')
      check(vim.tbl_contains(local_left, 'wt-branch'), '被 worktree 占用的分支必须被点名')
      check(not vim.tbl_contains(local_left, 'keep-me'), '已删分支不能误报为失败')

      local remote_left
      Delete.existing('remote', 'origin', function(names) remote_left = names end)
      wait(function() return remote_left ~= nil end, 5000, '远程查询未回调')
      check(vim.tbl_contains(remote_left, 'r-del'), '校验列表必须包含真实远程分支')

      local query_failed
      Delete.existing('remote', 'no-such-remote', function(names) query_failed = names == nil end)
      wait(function() return query_failed ~= nil end, 5000, '无效 remote 查询未回调')
      check(query_failed, '查询失败必须回调 nil，不能误报分支全部消失')
    end)
  end)
end

return T
