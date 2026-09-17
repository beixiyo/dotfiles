-- shared.git_async 契约：exit code 是唯一成败信号；stderr 成功丢弃（git push 非 TTY 下
-- 正常输出也走 stderr）、失败并入同一条 ERROR（错误文本不得以 INFO 弹出）；
-- on_success 仅成功执行，on_finally 恒调；yank 写双寄存器 + 通知
local this = debug.getinfo(1, 'S').source:sub(2)
local H = dofile(vim.fs.find('harness.lua', { upward = true, path = vim.fs.dirname(this) })[1])
local S = require('plugins.specs.ui.telescope.git.shared')

-- 成功路径：仅 on_exit_msg 一条 INFO
do
  local events = H.capture_notify(function()
    local ok_done, fin_code = false, nil
    S.git_async({ 'git', '--version' }, function() return 'ok msg' end,
      function() ok_done = true end,
      function(code) fin_code = code end)
    H.wait(function() return fin_code ~= nil end, 5000, 'git_async 未完成')
    H.check(ok_done, 'on_success 应在成功时执行')
    H.check(fin_code == 0, 'on_finally 应收到 code=0')
  end)
  H.eq(#events, 1, '成功路径应只有一条通知')
  H.check(events[1].msg == 'ok msg', '通知应来自 on_exit_msg')
  H.eq(events[1].level, vim.log.levels.INFO, '成功通知应为 INFO')
end

-- 失败路径：on_exit_msg 文案与 git stderr 合并为一条 ERROR；on_success 不执行
H.with_git_repo(function()
  local events = H.capture_notify(function()
    local ok_done, fin_code = false, nil
    S.git_async({ 'git', 'branch', '-D', 'nope' }, function() return 'base failed' end,
      function() ok_done = true end,
      function(code) fin_code = code end)
    H.wait(function() return fin_code ~= nil end, 5000, 'git_async 未完成')
    H.check(not ok_done, '失败时 on_success 不应执行')
    H.check(fin_code == 1, 'on_finally 应收到非零 code')
  end)
  H.eq(#events, 1, '失败路径应只有一条通知（stderr 并入，不单独弹）')
  H.eq(events[1].level, vim.log.levels.ERROR, '失败通知应为 ERROR')
  H.check(events[1].msg:find('base failed', 1, true) ~= nil, '应包含 on_exit_msg 文案')
  H.check(events[1].msg:find('branch', 1, true) ~= nil, '应并入 git stderr 原文')
end)

-- 成功但 stderr 有输出（push 的 To/NEW 行走 stderr）：不得产生额外通知
H.with_git_repo({ remote = true }, function(repo)
  H.git(repo.dir, 'branch', 'p1')
  local events = H.capture_notify(function()
    local fin_code
    S.git_async({ 'git', 'push', '-u', 'origin', 'p1' }, function() return 'pushed' end,
      nil, function(code) fin_code = code end)
    H.wait(function() return fin_code ~= nil end, 10000, 'push 未完成')
    H.check(fin_code == 0, 'push 应成功，fixture 问题则此处暴露')
  end)
  H.eq(#events, 1, '成功时 stderr 输出不得产生额外通知')
  H.check(events[1].msg == 'pushed', '唯一通知应来自 on_exit_msg')
end)

-- yank：双寄存器 + 通知文案
do
  local events = H.capture_notify(function() S.yank('dev', 'branch') end)
  H.eq(vim.fn.getreg('+'), 'dev', 'yank 应写入 + 寄存器')
  H.eq(vim.fn.getreg('"'), 'dev', 'yank 应写入 unnamed 寄存器')
  H.eq(#events, 1, 'yank 应弹一条通知')
  H.eq(events[1].msg, 'Copied branch: dev', 'yank 通知文案')
end

print('PASS: shared git_async notification policy and yank')
