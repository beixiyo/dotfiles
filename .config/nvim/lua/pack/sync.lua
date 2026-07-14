-- 同步已安装插件：卸载已从注册表移除的孤儿插件
local spec = require('pack.spec')

local M = {}

-- active_urls / disabled_urls 都是 url 表（string 或 { src = ... }）
function M.sync(active_urls, disabled_urls, disabled_set)
  local protected = {}
  for _, u in ipairs(active_urls) do protected[spec.get_name(u)] = true end
  for _, u in ipairs(disabled_urls) do
    local n = spec.get_name(u)
    protected[n] = true
    disabled_set[n] = true
  end

  local pack_dir = vim.fn.stdpath('data') .. '/site/pack'
  local installed = {}
  for _, pkg in ipairs(vim.fn.expand(pack_dir .. '/*', false, true)) do
    for _, t in ipairs({ 'start', 'opt' }) do
      local p = pkg .. '/' .. t
      if vim.fn.isdirectory(p) == 1 then
        for _, dir in ipairs(vim.fn.expand(p .. '/*', false, true)) do
          local n = dir:match('([^/]+)$')
          if n ~= 'README.md' and n ~= 'doc' then
            table.insert(installed, n)
          end
        end
      end
    end
  end

  local to_delete = {}
  for _, n in ipairs(installed) do
    if not protected[n] then table.insert(to_delete, n) end
  end

  if #to_delete > 0 then
    vim.schedule(function()
      vim.notify('🧹 Clean Up Orphaned Plugins: ' .. table.concat(to_delete, ', '), vim.log.levels.INFO)
      pcall(vim.pack.del, to_delete)
    end)
  end
end

return M
