-- data.lua 数据层契约：本地/远程统一解析、is_head/is_remote 分流、
-- /HEAD 过滤、feat/login 本地不得因剥首段丢类型、本地块在上远程在下
local this = debug.getinfo(1, 'S').source:sub(2)
local H = dofile(vim.fs.find('harness.lua', { upward = true, path = vim.fs.dirname(this) })[1])
local Data = require('plugins.specs.ui.telescope.git.branches.data')

local function entry_map(branches)
  local m = {}
  for _, e in ipairs(branches) do m[e.name] = e end
  return m
end

H.with_git_repo({ remote = true }, function(repo)
  -- fixture：本地 dev / feat/login / test-x；远程 feat/r + origin/HEAD
  H.git(repo.dir, 'branch', 'dev')
  H.git(repo.dir, 'branch', 'feat/login')
  H.git(repo.dir, 'branch', 'test-x')
  H.git(repo.dir, 'checkout', '-q', '-b', 'feat/r')
  H.git(repo.dir, 'push', '-q', '-u', 'origin', 'feat/r')
  H.git(repo.dir, 'checkout', '-q', 'main')
  H.git(repo.dir, 'remote', 'set-head', 'origin', '-a')

  local branches = Data.get_branches()
  local m = entry_map(branches)

  -- 本地解析与 is_head 标记（当前在 main）
  H.check(m['main'] ~= nil, '当前分支 main 应在列表')
  H.check(m['main'].is_head == true, 'main 应标记 is_head')
  H.check(m['main'].is_remote == false, 'main 不应是远程')
  H.check(m['dev'].branch_hl == 'VVBranchDev', 'dev 应映射 VVBranchDev')
  H.check(m['feat/login'].branch_hl == 'VVBranchFeat', 'feat/login 本地必须用全名判型，剥首段会丢 feat 类型')
  H.check(m['test-x'].branch_hl == 'VVBranchTest', 'test-x 应映射 VVBranchTest')

  -- 远程解析：剥 remote 前缀判型；origin/HEAD 过滤
  H.check(m['origin/main'] ~= nil, 'origin/main 应在列表')
  H.check(m['origin/main'].is_remote == true, 'origin/main 应标记 is_remote')
  H.check(m['origin/feat/r'].branch_hl == 'VVBranchFeat', 'origin/feat/r 应剥前缀后按 feat 判型')
  H.check(m['origin/HEAD'] == nil, 'origin/HEAD 应被过滤')

  -- 本地在上、远程在下
  local first_remote_idx
  for i, e in ipairs(branches) do
    if e.is_remote then
      first_remote_idx = i
      break
    end
  end
  H.check(first_remote_idx ~= nil, '应存在远程条目')
  for i = 1, first_remote_idx - 1 do
    H.check(not branches[i].is_remote, '本地块应全部位于远程块之前: ' .. branches[i].name)
  end

  -- entry 辅助字段齐备（init.lua 的 make_entry 依赖）
  for _, e in ipairs(branches) do
    H.check(type(e.subject) == 'string' and e.time_str and e.time_hl and e.branch_hl,
      'entry 缺展示字段: ' .. e.name)
  end
end)

-- parse_remote 契约：仅对确定远程的名字调用（不能用于判型，feat/login 会被拆开）
do
  local r, b = Data.parse_remote('origin/feat/login')
  H.eq({ r, b }, { 'origin', 'feat/login' }, '多级斜杠远程名应只拆出首段 remote')
  H.check(Data.parse_remote('main') == nil, '无斜杠名字应返回 nil')
end

print('PASS: branches data parsing, filtering and mapping')
