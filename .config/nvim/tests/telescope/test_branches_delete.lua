-- 批量删除编排契约：多选分组（is_head 跳过 / 远程剥前缀）+ 部分成功后的事后点名
-- 全链路场景：worktree 占用的分支 git 拒删 → existing 校验必须把它找回来、不误报已删者
local this = debug.getinfo(1, 'S').source:sub(2)
local H = dofile(vim.fs.find('harness.lua', { upward = true, path = vim.fs.dirname(this) })[1])
local Delete = require('plugins.specs.ui.telescope.git.branches.delete')

-- group()：混合 entries 分流（真实 entry 字段口径：value / is_head / is_remote）
do
  local grouped = Delete.group({
    { value = 'main',          is_head = true,  is_remote = false },
    { value = 'dev',           is_head = false, is_remote = false },
    { value = 'feat/login',    is_head = false, is_remote = false },
    { value = 'origin/feat/r', is_head = false, is_remote = true },
    { value = 'up/a/b',        is_head = false, is_remote = true },
    { value = 'bad',           is_head = false, is_remote = true },
  })
  H.eq(grouped.locals, { 'dev', 'feat/login' }, '本地分支应保持顺序进入 locals')
  H.eq(grouped.by_remote['origin'], { 'feat/r' }, 'origin/feat/r 应剥前缀进入 by_remote.origin')
  H.eq(grouped.by_remote['up'], { 'a/b' }, '多级斜杠远程应只剥首段')
  H.check(grouped.by_remote['bad'] == nil, '无斜杠的异常远程应被忽略')
  H.eq(grouped.skipped, 1, 'is_head 应计入 skipped')
end

H.with_git_repo({ remote = true }, function(repo)
  -- fixture：keep-me 可删，wt-branch 被 worktree 占用（git 拒删），r-del 远程分支
  H.git(repo.dir, 'branch', 'keep-me')
  H.git(repo.dir, 'branch', 'wt-branch')
  H.git(repo.dir, 'worktree', 'add', '-q', repo.base .. '/wt', 'wt-branch')
  H.git(repo.dir, 'push', '-q', 'origin', 'main:refs/heads/r-del')

  -- 模拟 picker 的批量删除：一条命令部分成功（keep-me 删掉，wt-branch 被拒）
  local _, code = H.git(repo.dir, 'branch', '-D', 'keep-me', 'wt-branch')
  H.check(code ~= 0, 'git 批量删除含被占用分支应整体 exit != 0')

  -- 事后校验：仍存在的 = 删除失败者，必须点名 wt-branch、不误报 keep-me
  local local_left
  Delete.existing('local', nil, function(names) local_left = names end)
  H.wait(function() return local_left ~= nil end, 5000, 'existing(local) 未回调')
  H.check(vim.tbl_contains(local_left, 'wt-branch'), '被 worktree 占用的 wt-branch 应被点名')
  H.check(not vim.tbl_contains(local_left, 'keep-me'), '已删除的 keep-me 不应误报')

  local remote_left
  Delete.existing('remote', 'origin', function(names) remote_left = names end)
  H.wait(function() return remote_left ~= nil end, 5000, 'existing(remote) 未回调')
  H.check(vim.tbl_contains(remote_left, 'r-del'), '远程现存分支应出现在校验列表')

  -- 查询失败路径：不存在的 remote → on_done(nil)，调用方据此报 Verify failed
  local query_failed
  Delete.existing('remote', 'no-such-remote', function(names) query_failed = (names == nil) end)
  H.wait(function() return query_failed ~= nil end, 5000, 'existing(坏 remote) 未回调')
  H.check(query_failed, '查询本身失败应回调 nil')
end)

print('PASS: branches delete grouping and partial-failure verification')
