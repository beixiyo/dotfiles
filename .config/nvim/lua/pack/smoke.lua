-- 冒烟测试：在当前 nvim 会话里验证 pack 架构的各层是否可用
-- 用法：:lua require('pack.smoke').run()
-- 不会真正加载插件，只做静态扫描 + 结构校验
local M = {}

local function head(s) return '== ' .. s .. ' ==' end

local function report(lines)
  vim.schedule(function()
    vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO, { title = 'pack smoke' })
  end)
  print(table.concat(lines, '\n'))
end

function M.run()
  local out = {}
  local function p(s) table.insert(out, s) end

  p(head('1) 模块加载'))
  local mods = { 'pack.spec', 'pack.sync', 'pack.build', 'pack.loader', 'pack.lazy', 'pack.scan', 'pack.stats' }
  for _, m in ipairs(mods) do
    local ok, err = pcall(require, m)
    p(('  %s %s'):format(ok and '✓' or '✗', m) .. (ok and '' or (' — ' .. tostring(err))))
  end

  p(head('2) 扫描 plugins/specs'))
  local scan = require('pack.scan')
  local specs = scan.collect()
  p(('  扫到 %d 个 spec'):format(#specs))
  for _, s in ipairs(specs) do
    local flags = {}
    if s.url then table.insert(flags, 'url') end
    if s.dir then table.insert(flags, 'dir') end
    if s.event or s.ft or s.cmd or s.keys then table.insert(flags, 'lazy-decl') end
    if s.lazy == 'manual' then table.insert(flags, 'lazy-manual') end
    if s.dependencies and #s.dependencies > 0 then table.insert(flags, 'dependencies=' .. #s.dependencies) end
    p(('  [%s/%s] %s  {%s}'):format(s.category or '?', s.id or '?', s.desc or '', table.concat(flags, ', ')))
  end

  p(head('3) spec 结构校验'))
  local errors = 0
  for _, s in ipairs(specs) do
    if not s.id then p('  ✗ 缺 id: ' .. (s._mod or '?')); errors = errors + 1 end
    if s.url and s.dir then p('  ✗ url/dir 互斥: ' .. s.id); errors = errors + 1 end
    if not s.url and not s.dir then p('  ✗ 缺 url/dir: ' .. s.id); errors = errors + 1 end
    if type(s.keys) == 'table' then
      for i, k in ipairs(s.keys) do
        if type(k) == 'table' and type(k[1]) ~= 'string' then
          p(('  ✗ %s.keys[%d] 首元素需为 string lhs'):format(s.id, i)); errors = errors + 1
        end
      end
    end
  end
  p(('  错误: %d'):format(errors))

  p(head('4) user-picks'))
  package.loaded['plugins.manager.user-picks'] = nil
  local ok, picks = pcall(require, 'plugins.manager.user-picks')
  p('  load: ' .. tostring(ok))
  if ok then
    local disabled = {}
    for id, v in pairs(picks) do if v == false then table.insert(disabled, id) end end
    table.sort(disabled)
    p('  disabled: [' .. table.concat(disabled, ', ') .. ']')
  end

  report(out)
end

return M
