-- git_async 的真实 Git 行为：成功的 stderr 不能误报，失败须合并为一条 ERROR
-- 回调、通知和 job 状态逐场景隔离，成功路径统一由真实 push 覆盖
local H = dofile('tests/helpers.lua')
local T, child = H.new_set()

T['成功 push 的 stderr 不误报且成功与收尾回调都执行'] = function()
  child.lua_func(function()
    local H = _G.H
    local S = require('plugins.specs.ui.telescope.git.shared')
    H.with_git_repo({ remote = true }, function(repo)
      local _, code = H.git(repo.dir, 'branch', 'p1')
      check(code == 0, '创建 push 分支失败')
      local events = H.capture_notify(function()
        local ok_done, fin_code = false, nil
        S.git_async({ 'git', 'push', '-u', 'origin', 'p1' }, function() return 'pushed' end,
          function() ok_done = true end, function(result) fin_code = result end)
        wait(function() return fin_code ~= nil end, 10000, 'push 未完成')
        check(ok_done, '成功时必须执行 on_success')
        eq(fin_code, 0, '成功的 on_finally 必须收到 code=0')
      end)
      eq(events, { { msg = 'pushed', level = vim.log.levels.INFO } },
        '成功 push 的 stderr 不能产生额外通知或被误报为 ERROR')
    end)
  end)
end

T['失败路径 stderr 并入同一条 ERROR 且只执行收尾回调'] = function()
  child.lua_func(function()
    local H = _G.H
    local S = require('plugins.specs.ui.telescope.git.shared')
    H.with_git_repo(function()
      local events = H.capture_notify(function()
        local ok_done, fin_code = false, nil
        S.git_async({ 'git', 'branch', '-D', 'nope' }, function() return 'base failed' end,
          function() ok_done = true end, function(code) fin_code = code end)
        wait(function() return fin_code ~= nil end, 5000, 'git_async 未完成')
        check(not ok_done, '失败时 on_success 不应执行')
        check(fin_code ~= 0, '失败的 on_finally 必须收到非零 code')
      end)
      eq(#events, 1, '失败路径应只有一条通知（stderr 并入，不单独弹）')
      eq(events[1].level, vim.log.levels.ERROR, '失败通知应为 ERROR')
      check(events[1].msg:find('base failed', 1, true) ~= nil, '应包含 on_exit_msg 文案')
      check(events[1].msg:find('branch', 1, true) ~= nil, '应并入 git stderr 原文')
    end)
  end)
end

return T
