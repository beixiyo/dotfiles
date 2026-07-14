-- pack 引擎入口：收集 spec → 过滤 → 下载 → 同步 → 加载
-- 替代 pack/init.lua；与 registry.lua 解耦（spec 自己声明元数据）
if not vim.pack then
  vim.notify(
    '[pack] vim.pack API 不存在，请升级 Neovim 到 0.12+。当前: ' .. tostring(vim.version()),
    vim.log.levels.ERROR
  )
  return
end

local scan = require('pack.scan')
local spec_mod = require('pack.spec')
local sync = require('pack.sync')
local loader = require('pack.loader')
local lazy = require('pack.lazy')
local stats = require('pack.stats')
local dev = require('pack.dev')

-- 在 wrap loader.load 之前完成 scan；stats.setup 会 monkey-patch loader.load
stats.setup(loader)

-- 加载用户禁用表（默认空，即全启用）
local function load_user_picks()
  local ok, picks = pcall(require, 'plugins.manager.user-picks')
  if ok and type(picks) == 'table' then return picks end
  return {}
end

local picks = load_user_picks()

-- 判断插件是否应加载
local function should_load(spec)
  if picks[spec.id] == false then return false end
  if vim.g.vscode and not spec.loadInVSCode then return false end

  if type(spec.cond) == 'function' then
    if not spec.cond() then return false end
  elseif spec.cond == false then
    return false
  end
  return true
end

-- 把主 spec 的 url + git 引用字段转成 vim.pack.add 的输入
-- 优先级：commit > tag > version > branch，统一写入 version 字段（vim.pack 的 version 同时接受 tag/branch/commit/semver）
local function to_pack_url(spec)
  local url = spec_mod.expand_url(spec.url)
  local ver = spec.commit or spec.tag or spec.version or spec.branch
  if ver == nil then return url end
  if type(url) == 'table' then
    local copy = vim.deepcopy(url)
    copy.version = copy.version or ver
    return copy
  end
  return { src = url, version = ver }
end

-- 收集所有 spec
local all_specs = scan.collect()

-- 本地 dev 覆盖：命中规则的 spec.url → spec.dir
-- 必须在 should_load / vim.pack.add 之前执行，否则远程 clone 抢先
local dev_skip = {}
for _, s in ipairs(all_specs) do
  local r = dev.redirect(s)
  if r == false then dev_skip[s.id or ''] = true end
end

-- ============ 分流：active / disabled，收集 url 去重 ============
local active_specs, disabled_urls = {}, {}
local unique_active, unique_disabled = {}, {}

local function add_url(list, seen, url)
  if not url then return end
  local expanded = spec_mod.expand_url(url)
  local k = spec_mod.url_str(expanded)

  if not seen[k] then
    -- 命中 dev 规则的 dependency：本地有就由对应主 spec 的 dev.dir 接管，不走 vim.pack 远程
    if dev.url_managed_locally(expanded) then
      seen[k] = true
      return
    end

    table.insert(list, expanded)
    seen[k] = true
  end
end

local active_urls = {}
for _, s in ipairs(all_specs) do
  if dev_skip[s.id or ''] then
    -- dev=true 强制本地但目录缺失且 fallback=false：跳过
  elseif should_load(s) then
    -- 主 spec 的 url 额外带上 git 引用字段
    local main_url = to_pack_url(s)
    local k = main_url and spec_mod.url_str(main_url) or nil
    if k and not unique_active[k] then
      table.insert(active_urls, main_url)
      unique_active[k] = true
    end
    if s.dependencies then
      for _, dep in ipairs(s.dependencies) do
        add_url(active_urls, unique_active, dep)
      end
    end
    table.insert(active_specs, s)
  else
    add_url(disabled_urls, unique_disabled, s.url)
    if s.dependencies then
      for _, dep in ipairs(s.dependencies) do
        add_url(disabled_urls, unique_disabled, dep)
      end
    end
  end
end

-- 同步：卸载孤儿，标记禁用集合
local disabled_set = {}
sync.sync(active_urls, disabled_urls, disabled_set)

-- 下载 GitHub 插件
if #active_urls > 0 then
  vim.pack.add(active_urls)
end

-- 按 priority 降序排序（大的先加载）；相同 priority 时保持 scan 顺序
-- 惯例：colorscheme / 共享库等"需要很早加载"的写大数值（100+）；默认 0
for i, s in ipairs(active_specs) do s._idx = i end
table.sort(active_specs, function(a, b)
  local pa, pb = a.priority or 0, b.priority or 0
  if pa ~= pb then return pa > pb end
  return a._idx < b._idx
end)

-- ============ 分发加载 ============
for _, s in ipairs(active_specs) do
  if s.lazy == 'manual' then
    -- 逃生舱：启动期立即调 config(plugin, { load = fn })，由 spec 自己决定加载时机
    -- 主要用于 treesitter 这类需要在 FileType 回调里按需安装 parser 的场景
    -- 不在此处记 stats：真正 packadd/加载发生在 ctx.load() 被触发时（loader wrap 会记一次）
    if type(s.config) == 'function' then
      local ok, err = pcall(s.config, s, {
        load = function() loader.load(s, disabled_set) end,
      })
      if not ok then
        vim.notify('[pack] ' .. (s.id or '?') .. ' manual config failed: ' .. tostring(err), vim.log.levels.ERROR)
      end
    end
  elseif lazy.has_triggers(s) then
    -- 声明式懒加载
    lazy.register(s, function() loader.load(s, disabled_set) end)
  else
    -- eager：立即加载
    loader.load(s, disabled_set)
  end
end

stats.finalize(#all_specs)

-- 把完整 spec 列表暴露给 manager GUI 读取（禁用的也要展示）
_G.Pack = _G.Pack or {}
_G.Pack.specs = all_specs
_G.Pack.picks = picks

-- 兼容/伪装 lazy.nvim 接口，使得第三方插件（tokyonight、which-key 等）能正常加载
require('pack.lazy-compat')

-- 注册 :PackUpdate / :PackStats / :PackGenTypes
require('pack.commands')

-- 监听 PackChanged，插件安装/更新后自动重新生成 .luarc.json
require('pack.luarc').setup()

-- 注册 :PluginManager 与 <leader>fp（与 pack 一致的用户界面）
require('plugins.manager.commands')
