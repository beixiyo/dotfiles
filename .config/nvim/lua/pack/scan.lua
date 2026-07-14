-- 扫描 plugins/specs/ 目录，收集所有 spec
-- 每个 spec 文件 return 一个 table；目录名 = category，文件名 = 默认 id
local M = {}

-- 扫描 plugins/specs/，支持两种形态：
--   1) <category>/<id>.lua        （单文件 spec）
--   2) <category>/<id>/init.lua   （目录 spec，<id>/ 下可放辅助模块）
-- 返回 spec 列表（已补全 id/category）。去重：同一 (category, id) 若两种都存在则目录优先
function M.collect()
  local config_root = vim.fn.stdpath('config')
  local root = config_root .. '/lua/plugins/specs/'

  -- 候选 entries：{ mod, category, id, rank }；rank 数值小者优先（目录 < 文件）
  local candidates = {}

  -- 形态 1：<category>/<id>.lua
  for _, f in ipairs(vim.fn.glob(root .. '*/*.lua', false, true)) do
    local category, id = f:match('plugins/specs/([^/]+)/([^/]+)%.lua$')
    if category and id and id ~= 'init' then
      table.insert(candidates, {
        mod = 'plugins.specs.' .. category .. '.' .. id,
        category = category, id = id, rank = 2,
      })
    end
  end

  -- 形态 2：<category>/<id>/init.lua
  for _, f in ipairs(vim.fn.glob(root .. '*/*/init.lua', false, true)) do
    local category, id = f:match('plugins/specs/([^/]+)/([^/]+)/init%.lua$')
    if category and id then
      table.insert(candidates, {
        mod = 'plugins.specs.' .. category .. '.' .. id,
        category = category, id = id, rank = 1,
      })
    end
  end

  -- 按 (category, id, rank) 去重：优先级更高（rank 更小）的覆盖
  local picked = {}
  for _, c in ipairs(candidates) do
    local k = c.category .. '/' .. c.id
    local cur = picked[k]
    if not cur or c.rank < cur.rank then picked[k] = c end
  end

  local specs = {}
  for _, c in pairs(picked) do
    -- 用 loadfile 而非 require：同名 foo.lua 与 foo/init.lua 并存时
    -- Lua require 总是先命中 foo.lua，但 dedup 优选 init.lua（rank 更低）；
    -- loadfile 直接指定路径，确保 dedup 结果生效
    local file = c.file or (root .. c.category .. '/' .. c.id
      .. (c.rank == 1 and '/init.lua' or '.lua'))
    local chunk, load_err = loadfile(file)
    if not chunk then
      vim.notify('[pack] 加载 spec 失败: ' .. c.mod .. '\n' .. tostring(load_err), vim.log.levels.ERROR)
    else
      local ok, spec = pcall(chunk)
      if not ok then
        vim.notify('[pack] 加载 spec 失败: ' .. c.mod .. '\n' .. tostring(spec), vim.log.levels.ERROR)
      elseif type(spec) ~= 'table' then
        vim.notify('[pack] spec 必须 return table: ' .. c.mod, vim.log.levels.ERROR)
      else
        package.loaded[c.mod] = spec
        spec.id = spec.id or c.id
        spec.category = spec.category or c.category
        spec._mod = c.mod
        table.insert(specs, spec)
      end
    end
  end

  return specs
end

return M
