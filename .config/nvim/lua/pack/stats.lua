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
  -- 加载会嵌套：A 的 config 里 require 懒加载的 B 时，B 在 A 的计时区间内完成
  -- 每层只记自身耗时（总耗时减去内层），各插件相加才等于真实开销
  local raw_load = loader_mod.load
  local resolve_name = require('pack.spec').resolve_name
  local inner_ns = {} ---@type number[] 栈：每一层已被内层加载占用的纳秒数
  loader_mod.load = function(spec, disabled_set)
    if loader_mod.is_loaded(resolve_name(spec)) then return end
    local depth = #inner_ns + 1
    inner_ns[depth] = 0
    local t0 = vim.uv.hrtime()
    local ok, r = pcall(raw_load, spec, disabled_set)
    local elapsed = vim.uv.hrtime() - t0
    local self_ns = elapsed - inner_ns[depth]
    inner_ns[depth] = nil
    if depth > 1 then inner_ns[depth - 1] = inner_ns[depth - 1] + elapsed end
    if not ok then error(r, 0) end

    table.insert(_G.PackStats.plugins, {
      name = spec.id or '?',
      ms = self_ns / 1e6,
      lazy = not not (spec.event or spec.ft or spec.cmd or spec.keys or spec.lazy == 'manual'),
    })
    return r
  end
end

function M.finalize(registered)
  if not _G.PackStats then return end
  _G.PackStats.total_ms = (vim.uv.hrtime() - _G.PackStats.start_hr) / 1e6
  _G.PackStats.registered = registered

  -- 没开启动页（带文件启动）时也要定格，否则之后手动打开 dashboard 会把使用时长算进去
  vim.api.nvim_create_autocmd('VimEnter', {
    once = true,
    callback = function() vim.schedule(M.startup_ms) end,
  })
end

---从 init.lua 开头到首次调用的耗时，首次调用后定格
---total_ms 只覆盖 pack 分发阶段；这个值还包含 config.* 与 VimEnter 回调，接近 --startuptime 的结果
---启动页在 VimEnter 渲染页脚时首次调用；其余情况由 finalize 注册的 VimEnter 回调兜底
---@return number ms
function M.startup_ms()
  local s = _G.PackStats
  if not s then return 0 end
  if not s.startup_ms then
    s.startup_ms = (vim.uv.hrtime() - (_G.NvimStartHr or s.start_hr)) / 1e6
  end
  return s.startup_ms
end

return M
