-- 分支数据获取与展示映射：纯函数，无 telescope 依赖
-- 本地/远程一律用 is_remote 判断，parse_remote 仅在确定远程后用于拆 remote/branch
-- （含 / 的本地分支如 feat/login 不能靠 parse_remote 判别，否则会被误当远程）
local M = {}

-- ── 高亮注册 ─────────────────────────────────────────────────────────────────

local _hl_ok = false

--- 注册分支高亮组（幂等；vv-utils.hl.register 自带 colorscheme 重挂）
function M.ensure_hl()
  if _hl_ok then return end
  _hl_ok = true
  require('vv-utils.hl').register('vv.git-branches.hl', {
    VVBranchHead   = { fg = '#e06c75', bold = true },  -- 当前分支的 * 标记，红
    VVBranchMain   = { fg = '#e06c75', bold = true },  -- main/master  红
    VVBranchFeat   = { fg = '#d19a66', bold = true },  -- feat*        橙
    VVBranchDev    = { fg = '#61afef', bold = true },  -- dev*         蓝
    VVBranchTest   = { fg = '#98c379', bold = true },  -- test*        绿
    VVBranchRemote = { fg = '#c678dd' },               -- 其他远程分支 紫
    VVBranchLocal  = { fg = '#abb2bf' },               -- 其他本地分支 灰白
    VVBranchAge1h  = { fg = '#56d364', bold = true },  -- < 1h   亮绿
    VVBranchAge12h = { fg = '#e3b341' },               -- < 12h  金黄
    VVBranchAge3d  = { fg = '#79c0ff' },               -- < 3d   浅蓝
    VVBranchAge7d  = { fg = '#768390' },               -- < 7d   灰蓝
    VVBranchAgeOld = { fg = '#444c56' },               -- ≥ 7d   暗灰
  })
end

-- ── 展示映射 ─────────────────────────────────────────────────────────────────

-- 按分支名匹配高亮组；优先级：main/master > test > dev > feat > 其他(远程紫/本地灰白)
-- 远程分支先剥掉 remote 名（首段）再判类型；本地分支用全名判类型
-- （本地 feat/login 若也剥首段会得到 login → 丢失 feat 类型，故必须分流）
local function branch_hl(name, is_remote)
  local base = is_remote and (name:match('^[^/]+/(.+)$') or name) or name
  if base == 'main' or base == 'master' then return 'VVBranchMain' end
  if base:match('^test')                then return 'VVBranchTest' end
  if base:match('^dev')                 then return 'VVBranchDev'  end
  if base:match('^feat')                then return 'VVBranchFeat' end
  return is_remote and 'VVBranchRemote' or 'VVBranchLocal'
end

local function time_fmt(ts)
  return os.date('%m-%d %H:%M:%S', ts)
end

local function time_hl(ts)
  local d = os.time() - ts
  if d < 3600       then return 'VVBranchAge1h'  end
  if d < 3600 * 12  then return 'VVBranchAge12h' end
  if d < 86400 * 3  then return 'VVBranchAge3d'  end
  if d < 86400 * 7  then return 'VVBranchAge7d'  end
  return 'VVBranchAgeOld'
end

-- ── 数据获取 ─────────────────────────────────────────────────────────────────

--- 一条 for-each-ref 取本地+远程：多个 --sort 时最后一个是主键
--- refname:rstrip=-2 只保留 refs/heads | refs/remotes 两段，按字典序本地在前；组内 committerdate 降序
--- 用完整 refname（非 :short）以便按前缀判断 is_remote，避免 feat/login 这类本地名被误判
--- 作为 argv 交给 finders.new_oneshot_job / systemlist，不经 shell，%09 由 git 展开为 tab
M.REFS_CMD = {
  'git', 'for-each-ref',
  '--sort=-committerdate',
  '--sort=refname:rstrip=-2',
  '--format=%(refname)%09%(committerdate:unix)%09%(HEAD)%09%(subject)',
  'refs/heads', 'refs/remotes',
}

--- 解析 REFS_CMD 的一行输出；/HEAD 符号引用、裸 remote 名与无法解析的行返回 nil
--- （async_oneshot_finder 会丢弃 entry_maker 返回的 nil）
---@param line string
---@return table?
function M.parse_ref_line(line)
  local ref, ts_str, head, subject = line:match('^([^\t]+)\t(%d+)\t([^\t]*)\t(.*)')
  if not ref then return nil end

  local name = ref:match('^refs/remotes/(.+)$')
  local is_remote = name ~= nil
  if not is_remote then name = ref:match('^refs/heads/(.+)$') end
  if not name or name:match('/HEAD$') then return nil end
  -- 过滤裸 remote 名（如 "origin"，不含 /）
  if is_remote and not name:find('/', 1, true) then return nil end

  local ts = tonumber(ts_str) or 0
  return {
    name      = name,
    ts        = ts,
    is_head   = head == '*',
    is_remote = is_remote,
    subject   = subject or '',
    time_str  = time_fmt(ts),
    time_hl   = time_hl(ts),
    branch_hl = branch_hl(name, is_remote),
  }
end

--- 'origin/feat/x' → 'origin', 'feat/x'（仅对确定远程的名字调用）
function M.parse_remote(name)
  return name:match('^([^/]+)/(.+)$')
end

return M
