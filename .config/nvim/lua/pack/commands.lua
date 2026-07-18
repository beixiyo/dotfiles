-- pack 引擎命令注册：
--   :PackUpdate [name ...]   无参更新全部；有参只更新指定插件，支持 tab 补全
--   :PackStats               打开性能分析浮窗（GUI）
--   :PackStatsEcho           在 :messages 打印性能文本（headless / 脚本用）

local function managed_names()
  local ok, list = pcall(vim.pack.get, nil, { info = false })
  if not ok or type(list) ~= 'table' then return {} end
  local names = {}
  for _, entry in ipairs(list) do
    local n = entry.spec and entry.spec.name
    if n then table.insert(names, n) end
  end
  table.sort(names)
  return names
end

local function complete_names(arglead)
  local out = {}
  for _, n in ipairs(managed_names()) do
    if arglead == '' or n:find(arglead, 1, true) == 1 then
      table.insert(out, n)
    end
  end
  return out
end

vim.api.nvim_create_user_command('PackUpdate', function(opts)
  local names = #opts.fargs > 0 and opts.fargs or nil
  vim.pack.update(names)
end, {
  nargs = '*',
  complete = complete_names,
  desc = '更新插件（无参更新全部；可指定一个或多个 pack 管理名）',
})

vim.api.nvim_create_user_command('PackStats', function()
  require('plugins.manager.stats').open()
end, { desc = '打开插件加载性能分析浮窗' })

vim.api.nvim_create_user_command('PackDev', function(opts)
  local dev = require('pack.dev')
  if #opts.fargs == 0 then
    local list = dev.list()
    if #list == 0 then
      vim.notify('[pack.dev] 当前无插件走本地 (path=' .. dev.config.path
        .. ', patterns=' .. table.concat(dev.config.patterns, ',') .. ')', vim.log.levels.INFO)
      return
    end
    local lines = { ('[pack.dev] %d plugin(s) using local source:'):format(#list) }
    for _, e in ipairs(list) do
      lines[#lines + 1] = ('  %-32s ← %s'):format(e.id or '?', e.dir)
    end
    vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO)
  else
    local info = dev.inspect(opts.fargs[1])
    if not info then
      vim.notify('[pack.dev] spec 不存在: ' .. opts.fargs[1], vim.log.levels.WARN)
      return
    end
    vim.notify(vim.inspect(info), vim.log.levels.INFO)
  end
end, {
  nargs = '?',
  complete = function() return _G.Pack and vim.tbl_map(function(s) return s.id end, _G.Pack.specs) or {} end,
  desc = '查看本地 dev 模式生效的插件（无参列全部；带 name 看判定细节）',
})

vim.api.nvim_create_user_command('PackGenTypes', function()
  require('pack.luarc').generate()
end, { desc = '重新生成 .luarc.json（扫描插件目录更新 lua_ls 类型库）' })

vim.api.nvim_create_user_command('PackStatsEcho', function()
  local s = _G.PackStats
  if not s then
    vim.notify('[pack] _G.PackStats 不存在（stats 未初始化）', vim.log.levels.WARN)
    return
  end

  local plugins = s.plugins or {}
  local sorted = vim.deepcopy(plugins)
  table.sort(sorted, function(a, b) return (a.ms or 0) > (b.ms or 0) end)

  local eager, lazy, eager_ms, lazy_ms = 0, 0, 0, 0
  for _, p in ipairs(plugins) do
    if p.lazy then
      lazy = lazy + 1
      lazy_ms = lazy_ms + (p.ms or 0)
    else
      eager = eager + 1
      eager_ms = eager_ms + (p.ms or 0)
    end
  end

  local lines = {
    '⚡ pack stats',
    ('  total:       %8.2f ms'):format(s.total_ms or 0),
    ('  vim.pack:    %8.2f ms'):format(s.add_ms or 0),
    ('  registered:  %d'):format(s.registered or 0),
    ('  loaded:      %d  (eager=%d / %.2f ms, lazy=%d / %.2f ms)')
      :format(#plugins, eager, eager_ms, lazy, lazy_ms),
    '',
    'top 20 slowest:',
  }
  for i = 1, math.min(20, #sorted) do
    local p = sorted[i]
    lines[#lines + 1] = ('  %-32s %8.2f ms  %s')
      :format(p.name or '?', p.ms or 0, p.lazy and '(lazy)' or '')
  end

  local chunks = {}
  for _, l in ipairs(lines) do chunks[#chunks + 1] = { l .. '\n' } end
  vim.api.nvim_echo(chunks, false, {})
end, { desc = '在 :messages 打印插件加载统计（无浮窗）' })
