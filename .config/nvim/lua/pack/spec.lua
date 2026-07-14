-- 插件 spec 处理：名称提取、url 展开、本地路径定位、main 模块推断

---@class PackKeySpec
---@field [1] string lhs
---@field [2]? string|fun() rhs
---@field mode? string|string[]
---@field desc? string
---@field ft? string|string[]
---@field noremap? boolean
---@field remap? boolean
---@field nowait? boolean
---@field silent? boolean
---@field expr? boolean

---@class PackSpec
---@field id? string
---@field desc? string
---@field url? string|{src: string, version?: string|vim.VersionRange}
---@field dir? string
---@field name? string
---@field main? string|false
---@field category? string
---@field priority? number
---@field lazy? 'manual'
---@field dev? boolean
---@field cond? boolean|fun(): boolean
---@field loadInVSCode? boolean
---@field dependencies? (string|{src: string, version?: string})[]
---@field build? string|string[]|fun(plugin: PackSpec)
---@field init? fun(plugin: PackSpec)
---@field opts? table|fun(plugin: PackSpec): table
---@field config? fun(plugin: PackSpec, opts?: table)
---@field event? string|string[]
---@field ft? string|string[]
---@field cmd? string[]
---@field keys? PackKeySpec[]|fun(plugin: PackSpec): PackKeySpec[]

local M = {}

-- 从 URL (字符串或 { src = ... } 表) 提取最后一段作为插件名
-- 兼容 'owner/repo' 短名、'https://github.com/owner/repo' 全路径，末尾 .git 自动去除
function M.get_name(url)
  local src = type(url) == 'table' and url.src or url
  if type(src) ~= 'string' then return nil end
  -- 先剥掉末尾斜杠，'https://github.com/owner/repo/' → 'repo'，避免 match 返回 nil 触发 :gsub 崩溃
  src = src:gsub('/+$', '')
  local seg = src:match('([^/]+)$')
  if not seg then return nil end
  return (seg:gsub('%.git$', ''))
end

-- 从 spec 推出 packadd 使用的插件名：url 优先，其次 dir 目录名，再次 id
function M.resolve_name(spec)
  if spec.name then return spec.name end
  if spec.url then return M.get_name(spec.url) end
  if spec.dir then return spec.dir:match('([^/]+)/?$') end
  return spec.id
end

-- 获取插件所在的本地根目录路径
function M.get_root(name)
  local paths = vim.api.nvim_get_runtime_file('pack/*/*/' .. name, true)
  if #paths > 0 then return paths[1] end
  local glob = vim.fn.globpath(vim.o.packpath, 'pack/*/*/' .. name, 0, 1)
  return glob[1] or nil
end

-- 提取 URL 的字符串部分（处理 url = { src = '...' } 的情况）
function M.url_str(url)
  return type(url) == 'table' and url.src or url
end

-- 'owner/repo' 短名 → 'https://github.com/owner/repo'；已是全路径则原样返回
-- 支持 { src = 'owner/repo', ... } 表形态：就地展开 src 字段
function M.expand_url(url)
  local src = type(url) == 'table' and url.src or url
  if type(src) ~= 'string' then return url end
  -- 已是完整 URL（含协议或 user@host 形式）
  if src:find('://', 1, true) or src:match('^%w[%w%-]*@') then
    return url
  end
  -- 短名：owner/repo，字符集允许字母数字 . _ -
  if src:match('^[%w%._%-]+/[%w%._%-]+$') then
    local full = 'https://github.com/' .. src
    if type(url) == 'table' then
      local copy = vim.deepcopy(url)
      copy.src = full
      return copy
    end
    return full
  end
  return url
end

-- lazy.nvim 同款 normname：用于自动推断 main 模块
-- 去 nvim- 前缀、.nvim/.vim 后缀、.lua/-lua 片段、非字母字符
function M.normname(name)
  local ret = name:lower():gsub('^n?vim%-', ''):gsub('%.n?vim$', ''):gsub('[%.%-]lua', ''):gsub('[^a-z]+', '')
  return ret
end

-- 解析 main 模块名：显式 main 优先 → main = false 明确跳过 → 否则扫 dir/lua/ 推断
-- 返回：string 模块名 / false 不 require / nil 推断不出（等价 false）
function M.resolve_main(spec)
  if spec.main ~= nil then return spec.main end
  local name = M.resolve_name(spec)

  if not name then return nil end
  local dir = spec.dir or M.get_root(name)

  if not dir then return nil end
  local lua_dir = dir .. '/lua'

  if vim.fn.isdirectory(lua_dir) == 0 then return nil end
  -- mini.* 系列直接用 plugin 名（mini.pairs、mini.icons ...）
  if name ~= 'mini.nvim' and name:match('^mini%..*$') then return name end

  local norm = M.normname(name)
  local candidates = {}

  for _, item in ipairs(vim.fn.readdir(lua_dir)) do
    local mod = item:gsub('%.lua$', '')
    if mod ~= '' then
      if M.normname(mod) == norm then return mod end
      table.insert(candidates, mod)
    end
  end

  -- 未精确匹配：只有一个候选时接受，否则交给用户显式指定
  if #candidates == 1 then return candidates[1] end
  return nil
end

return M
