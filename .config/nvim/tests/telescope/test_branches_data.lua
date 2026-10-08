-- data.lua 数据层契约：单条 REFS_CMD + parse_ref_line 必须复现旧的两次查询结果——
-- 本地块在上、远程块在下、各块 committerdate 降序（远程更新也不得插到本地前）；
-- is_head/is_remote 分流、/HEAD 过滤、feat/login 本地不得因剥首段丢类型
local H = dofile('tests/helpers.lua')
local MiniTest = require('mini.test')
local T = MiniTest.new_set()
local Data = require('plugins.specs.ui.telescope.git.branches.data')

T['单次查询的排序、分流与判型'] = function()
  -- 在 dir 上以指定 committer 时间提交空 commit（时间决定 for-each-ref 排序）
  local function commit_at(dir, date, msg)
    local saved = vim.env.GIT_COMMITTER_DATE
    vim.env.GIT_COMMITTER_DATE = date
    local _, code = H.git(dir, 'commit', '-q', '--allow-empty', '-m', msg)
    vim.env.GIT_COMMITTER_DATE = saved
    H.check(code == 0, '创建定时提交失败：' .. msg)
  end

  local function load_branches()
    local lines = vim.fn.systemlist(Data.REFS_CMD)
    H.check(vim.v.shell_error == 0, 'REFS_CMD 执行失败: ' .. table.concat(lines, '\n'))
    local items = {}
    for _, line in ipairs(lines) do
      local item = Data.parse_ref_line(line)
      if item then items[#items + 1] = item end
    end
    return items
  end

  H.with_git_repo({ remote = true }, function(repo)
    local function must_git(...)
      local out, code = H.git(repo.dir, ...)
      H.eq(code, 0, '建立分支 fixture 失败：' .. table.concat(out, '\n'))
    end
    -- main 固定为 2026，排序断言不依赖运行机器的时钟
    commit_at(repo.dir, '2026-01-01T00:00:00Z', 'main')
    must_git('push', '-q', 'origin', 'main')
    -- fixture：本地 feat/r(2025) > feat/login(2021) > dev(2020) > test-x(2019)
    -- feat/r 推到远程：origin/feat/r 比所有旧本地分支都新，纯按时间排序会把它插进本地块
    local branches_by_date = {
      { 'test-x',     '2019-01-01T00:00:00Z' },
      { 'dev',        '2020-01-01T00:00:00Z' },
      { 'feat/login', '2021-01-01T00:00:00Z' },
      { 'feat/r',     '2025-01-01T00:00:00Z' },
    }
    for _, b in ipairs(branches_by_date) do
      must_git('checkout', '-q', '-b', b[1], 'main')
      commit_at(repo.dir, b[2], 'on ' .. b[1])
    end
    must_git('push', '-q', '-u', 'origin', 'feat/r')
    must_git('checkout', '-q', 'main')
    must_git('remote', 'set-head', 'origin', '-a')

    local branches = load_branches()
    local names, m = {}, {}
    for _, e in ipairs(branches) do
      names[#names + 1] = e.name
      m[e.name] = e
    end

    H.eq(names, {
      'main', 'feat/r', 'feat/login', 'dev', 'test-x',
      'origin/main', 'origin/feat/r',
    }, '应本地块在上、远程块在下，各块按 committerdate 降序，且 origin/HEAD 被过滤')

    -- 本地解析与 is_head 标记（当前在 main）
    H.check(m['main'].is_head == true, 'main 应标记 is_head')
    H.check(m['main'].is_remote == false, 'main 不应是远程')
    H.check(m['feat/login'].is_remote == false, 'feat/login 含 / 但是本地分支，不得判为远程')
    H.check(m['dev'].branch_hl == 'VVBranchDev', 'dev 应映射 VVBranchDev')
    H.check(m['feat/login'].branch_hl == 'VVBranchFeat', 'feat/login 本地必须用全名判型，剥首段会丢 feat 类型')
    H.check(m['test-x'].branch_hl == 'VVBranchTest', 'test-x 应映射 VVBranchTest')
    H.eq(m['dev'].subject, 'on dev', 'subject 应来自 ref 指向的 commit')

    -- 远程解析：剥 refs/remotes/ 前缀后按 remote/branch 展示，判型再剥 remote 名
    H.check(m['origin/feat/r'].is_remote == true, 'origin/feat/r 应标记 is_remote')
    H.check(m['origin/feat/r'].branch_hl == 'VVBranchFeat', 'origin/feat/r 应剥前缀后按 feat 判型')
  end)
end

return T
