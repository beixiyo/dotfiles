-- 懒加载插件的按需兜底
--
-- 远程插件在 vim.pack.add 阶段只安装、不挂 rtp（见 pack/init.lua 的 load 回调），
-- 声明式触发器之外还有三条路径会用到尚未加载的插件，这里统一兜住：
--   1. require('<插件模块>')  —— 先完整加载所属 spec（含 config），再交给后续 loader 解析
--   2. 未定义的用户命令       —— 命令名前缀与插件名匹配时加载该插件，由 Neovim 重新解析命令
--   3. :help                  —— 首次进入命令行时把未加载插件追加到 rtp 末尾，使其 doc/tags 可查
--
-- 只覆盖远程插件；本地 vendor（spec.dir）保持原有语义，仍由自己的触发器加载
local spec_mod = require('pack.spec')

local M = {}

---@class PackOndemandEntry
---@field name string packadd 使用的插件目录名
---@field path string 插件根目录
---@field load fun() 幂等加载：主插件走 loader.load，纯依赖只 packadd
---@field is_dep boolean 仅作为其它 spec 的依赖出现

---@type table<string, PackOndemandEntry> 插件目录名 → 条目；加载后移除
local pending = {}

---@type table<string, string[]>|nil 顶层 Lua 模块名 → 插件目录名列表；首次 require 时构建
local topmods

-- 多个插件可共享顶层模块（telescope.nvim 与各扩展都有 lua/telescope/）
-- 主插件排在纯依赖前面：先完整加载主插件，它的 dependencies 随之挂载
local function build_topmods()
  topmods = {}
  local names = vim.tbl_keys(pending)
  table.sort(names, function(x, y)
    if pending[x].is_dep ~= pending[y].is_dep then return not pending[x].is_dep end
    return x < y
  end)

  for _, name in ipairs(names) do
    local handle = vim.uv.fs_scandir(pending[name].path .. '/lua')
    while handle do
      local item = vim.uv.fs_scandir_next(handle)
      if not item then break end
      local mod = item:gsub('%.lua$', '')
      topmods[mod] = topmods[mod] or {}
      table.insert(topmods[mod], name)
    end
  end
end

---取出并移除条目后再加载：加载过程中的 require / 命令不会重入同一插件
---@param name string
local function take_and_load(name)
  local entry = pending[name]
  if not entry then return end
  pending[name] = nil
  entry.load()
end

-- package.loaders 约定：返回 nil 表示「不归我管」，继续走后面的 loader
local function searcher(modname)
  if next(pending) == nil then return nil end
  if not topmods then build_topmods() end

  for _, name in ipairs(topmods[modname:match('^[^.]+')] or {}) do
    take_and_load(name)
  end
  return nil
end

---按命令名前缀找所属插件，多个命中时取最长匹配
---Telescope → telescope.nvim、ConformInfo → conform.nvim、DapViewOpen → nvim-dap-view 而非 nvim-dap
---@param cmd string
---@return string|nil
local function plugin_for_cmd(cmd)
  local norm_cmd = cmd:lower():gsub('[^a-z]+', '')
  local best, best_len = nil, 0
  for name in pairs(pending) do
    local norm = spec_mod.normname(name)
    if #norm > best_len and norm_cmd:sub(1, #norm) == norm then
      best, best_len = name, #norm
    end
  end
  return best
end

---@class PackOndemandOpts
---@field specs PackSpec[] 已注册触发器、尚未加载的 spec
---@field load fun(spec: PackSpec) 加载一个 spec（幂等）

---@param opts PackOndemandOpts
function M.setup(opts)
  -- 启动期已被 eager spec 挂载的目录（含共享依赖）不需要兜底
  local mounted = {}
  for _, p in ipairs(vim.api.nvim_list_runtime_paths()) do mounted[p] = true end

  -- vim.pack 的固定安装位置；直接 stat，避免 get_root 对每个插件做一次全 rtp glob
  local opt_root = vim.fn.stdpath('data') .. '/site/pack/core/opt/'

  local function add(name, load, is_dep)
    if not name or pending[name] then return end
    local path = opt_root .. name
    if not mounted[path] and vim.uv.fs_stat(path) then
      pending[name] = { name = name, path = path, load = load, is_dep = is_dep }
    end
  end

  -- 先登记主插件再登记依赖：同一插件既是某 spec 的主体又是另一 spec 的依赖时，以主体为准
  for _, s in ipairs(opts.specs) do
    if s.url then
      add(spec_mod.resolve_name(s), function() opts.load(s) end, false)
    end
  end
  for _, s in ipairs(opts.specs) do
    for _, dep in ipairs(s.dependencies or {}) do
      local dep_name = spec_mod.get_name(dep)
      add(dep_name, function() pcall(vim.cmd.packadd, dep_name) end, true)
    end
  end

  if next(pending) == nil then return end

  -- 排在 preload 之后、vim.loader 之前：插件即使已被 :help 兜底挂上 rtp，require 仍先走完整加载
  table.insert(package.loaders, 2, searcher)

  local group = vim.api.nvim_create_augroup('PackOndemand', { clear = true })

  vim.api.nvim_create_autocmd('CmdUndefined', {
    group = group,
    callback = function(ev)
      local name = plugin_for_cmd(ev.match)
      if name then take_and_load(name) end
    end,
  })

  vim.api.nvim_create_autocmd('CmdlineEnter', {
    group = group,
    pattern = ':',
    once = true,
    callback = function()
      local paths = {}
      for _, entry in pairs(pending) do
        if vim.uv.fs_stat(entry.path .. '/doc') then paths[#paths + 1] = entry.path end
      end
      table.sort(paths)
      if #paths > 0 then vim.opt.rtp:append(paths) end
    end,
  })
end

---spec 即将加载时调用，停止对它及其依赖的兜底
---@param spec PackSpec
function M.forget(spec)
  local name = spec.url and spec_mod.resolve_name(spec)
  if name then pending[name] = nil end
  for _, dep in ipairs(spec.dependencies or {}) do
    local dep_name = spec_mod.get_name(dep)
    if dep_name then pending[dep_name] = nil end
  end
end

return M
