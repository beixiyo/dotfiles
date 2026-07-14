-- lazy.nvim 兼容层
-- 使依赖 lazy.nvim 接口的第三方插件（tokyonight、which-key 等）在不安装 lazy.nvim 的前提下正常加载
-- 实现细节参考 https://github.com/folke/lazy.nvim

local spec_mod = require('pack.spec')

-- 阻止 require('lazy') 报错，which-key 通过 package.loaded.lazy 判断是否启用 lazy.nvim 集成
package.loaded.lazy = true

-- lazy.core.config — tokyonight.nvim 通过它获取已启用插件列表，用于生成高亮组
package.preload['lazy.core.config'] = function()
  local plugins = {}
  local picks = _G.Pack and _G.Pack.picks or {}
  for _, s in ipairs(_G.Pack and _G.Pack.specs or {}) do
    if picks[s.id] ~= false then
      local name = spec_mod.resolve_name(s)
      if name then
        plugins[name] = true
      end
      if s.id then
        plugins[s.id] = true
      end
      if s.name then
        plugins[s.name] = true
      end
    end
  end
  return { plugins = plugins }
end

-- lazy.core.util — which-key 需要 normname 来规范化插件名
package.preload['lazy.core.util'] = function()
  local M = {}
  -- 从 lazy.nvim 源码复刻：https://github.com/folke/lazy.nvim/blob/main/lua/lazy/core/util.lua
  function M.normname(name)
    local ret = name:lower():gsub("^n?vim%-", ""):gsub("%.n?vim$", ""):gsub("[%.%-]lua", ""):gsub("[^a-z]+", "")
    return ret
  end
  return M
end

-- lazy.core.handler — which-key 通过它解析 keymap 并查找所属插件
-- 参考：https://github.com/folke/lazy.nvim/blob/main/lua/lazy/core/handler/keys.lua
package.preload['lazy.core.handler'] = function()
  local Keys = {}

  -- Managed 表由 lazy.nvim 在插件启用时填充，此处保持空，which-key 的查询静默返回 nil
  Keys.managed = {}

  function Keys.parse(value, mode)
    value = type(value) == "string" and { value } or value
    local ret = vim.deepcopy(value)
    ret.lhs = ret[1] or ""
    ret.rhs = ret[2]
    ret[1] = nil
    ret[2] = nil
    ret.mode = mode or "n"
    ret.id = vim.api.nvim_replace_termcodes(ret.lhs, true, true, true)
    if ret.ft then
      local ft = type(ret.ft) == "string" and { ret.ft } or ret.ft
      ret.id = ret.id .. " (" .. table.concat(ft, ", ") .. ")"
    end
    if ret.mode ~= "n" then
      ret.id = ret.id .. " (" .. ret.mode .. ")"
    end
    return ret
  end

  return {
    handlers = {
      keys = Keys,
    },
  }
end
