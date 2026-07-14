-- 本地开发覆盖（与 lazy.nvim 的 `dev = {...}` 等价）
-- 命中规则的 spec：spec.url → spec.dir，让 pack 走本地源码而非远程 clone
--
-- 触发方式（任一）：
--   1. spec.url 命中 M.config.patterns（默认匹配 owner 名子串）
--   2. spec 显式 `dev = true`（强制走本地，本地不存在时回退远程并 warn）
--   3. spec 显式 `dev = false`（永远走远程，即使命中 patterns）
--
-- 调试：
--   :PackDev          列出当前 dev 模式生效的插件
--   :PackDev <name>   只看某个插件的判定结果
local spec_mod = require('pack.spec')

local M = {}

-- ============ 用户配置 ============
---@class PackDevConfig
---@field path string 本地仓库父目录（每个插件一个子目录，目录名 == repo 名）
---@field patterns string[] url 子串匹配；命中即走本地（典型用法：自己的 GitHub owner）
---@field fallback boolean 本地目录不存在时：true=回退远程 clone，false=直接跳过该插件
M.config = {
  path = vim.fn.stdpath('config') .. '/vendors',
  patterns = { 'beixiyo' },
  fallback = true,
}

-- 允许外部覆盖配置（启动早期调用）
function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
end

-- 给定 spec 推算本地 dir 路径（不检查是否存在）
-- 优先按 url 推（GitHub repo 名，含 .nvim 后缀），再退回 spec.name / dir 名
local function local_dir_for(spec)
  if spec.url then
    local name = spec_mod.get_name(spec.url)
    if name then return M.config.path .. '/' .. name end
  end

  local name = spec_mod.resolve_name(spec)
  if not name then return nil end
  return M.config.path .. '/' .. name
end

-- 判断一个 url 是否命中 patterns
local function url_matches(url)
  if not url then return false end
  local src = type(url) == 'table' and url.src or url
  if type(src) ~= 'string' then return false end
  for _, pat in ipairs(M.config.patterns) do
    if src:find(pat, 1, true) then return true end
  end
  return false
end

-- 判断 dependency URL 是否应该跳过 vim.pack 下载
-- （命中 patterns 且本地有，由对应主 spec 接管 rtp）
function M.url_managed_locally(url)
  if not url_matches(url) then return false end
  local name = spec_mod.get_name(url)

  if not name then return false end
  local dir = M.config.path .. '/' .. name
  return vim.fn.isdirectory(dir) == 1
end

-- 决定 spec 是否应该走 dev：
--   返回 dir 路径（应走 dev 且本地存在）
--   返回 nil（不走 dev，或本地缺失且 fallback=true）
--   返回 false（dev=true 强制但本地缺失且 fallback=false → 调用方应跳过）
local function resolve(spec)
  -- 已经是本地 vendor（spec.dir 直接给的），不参与 dev 逻辑
  if spec.dir then return nil end

  local force = spec.dev
  if force == false then return nil end

  local matched = (force == true) or url_matches(spec.url)
  if not matched then return nil end

  local dir = local_dir_for(spec)
  if not dir then return nil end

  if vim.fn.isdirectory(dir) == 1 then return dir end

  -- 本地不存在
  local name = spec_mod.resolve_name(spec) or '?'
  if force == true then
    vim.notify(
      ('[pack.dev] %s: dev=true 但 %s 不存在'):format(name, dir)
        .. (M.config.fallback and '，回退远程 clone' or '，已跳过'),
      vim.log.levels.WARN
    )
  end
  if M.config.fallback then return nil end
  return false
end

-- 命中 dev 时把 spec.url → spec.dir，原 url 备份到 spec._dev_origin_url
-- 返回：
--   true       已重定向到本地
--   false      dev=true 强制但本地缺失且 fallback=false（调用方应跳过此 spec）
--   nil        未触发 dev 逻辑（继续走远程）
function M.redirect(spec)
  local dir = resolve(spec)
  if dir == nil then return nil end
  if dir == false then return false end

  spec._dev_origin_url = spec.url
  spec.dir = dir
  spec.url = nil
  return true
end

-- 列出当前 dev 模式生效的插件（供 :PackDev 命令使用）
function M.list()
  local out = {}
  for _, s in ipairs(_G.Pack and _G.Pack.specs or {}) do
    if s._dev_origin_url then
      table.insert(out, {
        id = s.id,
        dir = s.dir,
        origin = type(s._dev_origin_url) == 'table' and s._dev_origin_url.src or s._dev_origin_url,
      })
    end
  end
  table.sort(out, function(a, b) return (a.id or '') < (b.id or '') end)
  return out
end

-- 单个 spec 的判定细节（供 :PackDev <name> 使用）
function M.inspect(name)
  for _, s in ipairs(_G.Pack and _G.Pack.specs or {}) do
    if s.id == name or spec_mod.resolve_name(s) == name then
      return {
        id = s.id,
        url = s._dev_origin_url or s.url,
        dir = s.dir,
        dev = s.dev,
        active = s._dev_origin_url ~= nil,
        local_path = local_dir_for(s),
        local_exists = (function()
          local d = local_dir_for(s)
          return d and vim.fn.isdirectory(d) == 1 or false
        end)(),
      }
    end
  end
  return nil
end

return M
