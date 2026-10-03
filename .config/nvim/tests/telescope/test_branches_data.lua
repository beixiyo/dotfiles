-- data.lua 数据层契约：单条 REFS_CMD + parse_ref_line 必须复现旧的两次查询结果——
-- 本地块在上、远程块在下、各块 committerdate 降序（远程更新也不得插到本地前）；
-- is_head/is_remote 分流、/HEAD 过滤、feat/login 本地不得因剥首段丢类型
local this = debug.getinfo(1, 'S').source:sub(2)
local H = dofile(vim.fs.find('harness.lua', { upward = true, path = vim.fs.dirname(this) })[1])
local Data = require('plugins.specs.ui.telescope.git.branches.data')

-- 在 dir 上以指定 committer 时间提交空 commit（时间决定 for-each-ref 排序）
local function commit_at(dir, date, msg)
  local saved = vim.env.GIT_COMMITTER_DATE
  vim.env.GIT_COMMITTER_DATE = date
  local _, code = H.git(dir, 'commit', '-q', '--allow-empty', '-m', msg)
  vim.env.GIT_COMMITTER_DATE = saved
  H.check(code == 0, 'fixture commit failed: ' .. msg)
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
  -- fixture：本地 feat/r(2025) > feat/login(2021) > dev(2020) > test-x(2019)，main 为当前时间
  -- feat/r 推到远程：origin/feat/r 比所有旧本地分支都新，纯按时间排序会把它插进本地块
  local branches_by_date = {
    { 'test-x',     '2019-01-01T00:00:00Z' },
    { 'dev',        '2020-01-01T00:00:00Z' },
    { 'feat/login', '2021-01-01T00:00:00Z' },
    { 'feat/r',     '2025-01-01T00:00:00Z' },
  }
  for _, b in ipairs(branches_by_date) do
    H.git(repo.dir, 'checkout', '-q', '-b', b[1], 'main')
    commit_at(repo.dir, b[2], 'on ' .. b[1])
  end
  H.git(repo.dir, 'push', '-q', '-u', 'origin', 'feat/r')
  H.git(repo.dir, 'checkout', '-q', 'main')
  H.git(repo.dir, 'remote', 'set-head', 'origin', '-a')

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

-- parse_ref_line 过滤：符号引用 /HEAD、裸 remote 名、非 heads/remotes ref、格式不符的行
do
  local function line(ref) return ref .. '\t1700000000\t \tsubj' end
  H.check(Data.parse_ref_line(line('refs/remotes/origin/HEAD')) == nil, 'refs/remotes/origin/HEAD 应过滤')
  H.check(Data.parse_ref_line(line('refs/remotes/origin')) == nil, '裸 remote 名应过滤')
  H.check(Data.parse_ref_line(line('refs/tags/v1')) == nil, '非 heads/remotes ref 应过滤')
  H.check(Data.parse_ref_line('') == nil, '空行应返回 nil（finder 丢弃 nil）')
end

-- parse_remote 契约：仅对确定远程的名字调用（不能用于判型，feat/login 会被拆开）
do
  local r, b = Data.parse_remote('origin/feat/login')
  H.eq({ r, b }, { 'origin', 'feat/login' }, '多级斜杠远程名应只拆出首段 remote')
  H.check(Data.parse_remote('main') == nil, '无斜杠名字应返回 nil')
end

print('PASS: branches data parsing, filtering, ordering and mapping')
