-- 插件加载性能统计：复用 _G.PackStats（stats UI 已依赖此全局）
-- 通过 wrap loader.load / vim.pack.add 记录耗时
local M = {}

function M.setup(loader_mod)
  _G.PackStats = { start_hr = vim.uv.hrtime(), add_ms = 0, plugins = {}, total_ms = 0 }

  -- 包装 vim.pack.add 累计下载/检查耗时
  local raw_add = vim.pack.add
  vim.pack.add = function(specs, opts)
    local t0 = vim.uv.hrtime()
    local r = raw_add(specs, opts)
    _G.PackStats.add_ms = _G.PackStats.add_ms + (vim.uv.hrtime() - t0) / 1e6
    return r
  end

  -- 包装 loader.load 记录每个插件加载耗时
  -- 已加载的 spec 直接让 raw_load 幂等退出，不重复计入 stats
  local raw_load = loader_mod.load
  local resolve_name = require('pack.spec').resolve_name
  loader_mod.load = function(spec, disabled_set)
    if loader_mod.is_loaded(resolve_name(spec)) then return end
    local t0 = vim.uv.hrtime()
    local r = raw_load(spec, disabled_set)
    table.insert(_G.PackStats.plugins, {
      name = spec.id or '?',
      ms = (vim.uv.hrtime() - t0) / 1e6,
      lazy = not not (spec.event or spec.ft or spec.cmd or spec.keys or spec.lazy == 'manual'),
    })
    return r
  end
end

function M.finalize(registered)
  if not _G.PackStats then return end
  _G.PackStats.total_ms = (vim.uv.hrtime() - _G.PackStats.start_hr) / 1e6
  _G.PackStats.registered = registered
end

return M
