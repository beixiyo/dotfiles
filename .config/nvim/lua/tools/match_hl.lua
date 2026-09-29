-- 搜索匹配高亮：派生统一的 VVMatch（强调色 fg + 同色相淡底），供 fff / vv-symbols 等 picker 共用
-- 强调色优先取 tokyonight 色板的 search_match（语法色未占用的色相），非 tokyonight 或缺字段时退回 IncSearch.bg
-- fg 不能省：fff preview 目标行的 line_hl_group 会吞掉匹配段 bg，只有 fg / bold 能穿透，靠它区分当前行上的匹配
-- tokyonight.load() 不触发 ColorScheme，且调用方 spec 可能先于主题加载，所以首次派生推迟到 vim.schedule

---@class tools.match_hl
local M = {}

--- 统一匹配高亮组名
M.group = 'VVMatch'

--- 淡底混合比例：越大越接近主题搜索色
local AMOUNT = 0.25

local aliases = {} ---@type table<string, true>
local registered = false

local function get(name) return vim.api.nvim_get_hl(0, { name = name, link = false }) end

local function apply()
  local Color = require('vv-utils.color')
  local themed = (vim.g.colors_name or ''):match('^tokyonight%-') and require('tools.palette').get().search_match
  local accent = themed or get('IncSearch').bg or get('Search').bg or 0xe5c07b
  local base = get('Normal').bg or 0x000000
  vim.api.nvim_set_hl(0, M.group, {
    fg = accent,
    bg = Color.to_integer(Color.mix(base, accent, AMOUNT)),
    bold = true,
  })
  -- 非 default 链接：插件自己的 default=true 注册不会反向覆盖
  for name in pairs(aliases) do vim.api.nvim_set_hl(0, name, { link = M.group }) end
end

--- 把插件的匹配高亮组链接到 VVMatch，幂等；ColorScheme 后自动重建
---@param names string[] 高亮组名
function M.link(names)
  for _, name in ipairs(names) do aliases[name] = true end
  if not registered then
    registered = true
    vim.api.nvim_create_autocmd('ColorScheme', {
      group = vim.api.nvim_create_augroup('VVMatchHl', { clear = true }),
      callback = function() vim.schedule(apply) end,
    })
  end
  vim.schedule(apply)
end

return M
