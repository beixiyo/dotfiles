-- pack 引擎命令注册：
--   :PackStats               打开插件管理界面的耗时标签
--   :PackStatsEcho           在 :messages 打印性能文本（headless / 脚本用）
-- 更新插件用内置的 :packupdate [name ...]

vim.api.nvim_create_user_command('PackStats', function()
  require('plugins.manager').open('stats')
end, { desc = 'Open the plugin manager on the load stats tab' })

vim.api.nvim_create_user_command('PackDev', function(opts)
  local dev = require('pack.dev')
  if #opts.fargs == 0 then
    local list = dev.list()
    if #list == 0 then
      vim.notify('[pack.dev] no plugins use local source (path=' .. dev.config.path
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
      vim.notify('[pack.dev] spec not found: ' .. opts.fargs[1], vim.log.levels.WARN)
      return
    end
    vim.notify(vim.inspect(info), vim.log.levels.INFO)
  end
end, {
  nargs = '?',
  complete = function() return _G.Pack and vim.tbl_map(function(s) return s.id end, _G.Pack.specs) or {} end,
  desc = 'Show plugins using local dev mode (no args: list all; with name: show resolution details)',
})

vim.api.nvim_create_user_command('PackGenTypes', function()
  require('pack.luarc').generate()
end, { desc = 'Regenerate .luarc.json (rescan plugin dirs and update lua_ls type libraries)' })

vim.api.nvim_create_user_command('PackStatsEcho', function()
  local s = _G.PackStats
  if not s then
    vim.notify('[pack] _G.PackStats is missing (stats not initialized)', vim.log.levels.WARN)
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
end, { desc = 'Print plugin load stats to :messages (no float)' })
