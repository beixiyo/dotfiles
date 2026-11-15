-- ================================
-- 插件管理界面：:PluginManager（启用 / 禁用）与 :PackStats（加载耗时）是同一个浮窗的两个标签
-- 数据源：_G.Pack.specs、_G.PackStats（启动期由 pack 写入）、pack.loader 的加载状态
-- 状态源：user-picks.lua（默认全启用，只记录禁用集合）
-- 窗口、标签栏、分组、展开详情、光标保持都来自 vv-utils.ui_view，这里只描述每页的内容
-- ================================

local M = {}

local CATEGORY_ORDER = { 'code', 'tools', 'ui' }
local CATEGORY_LABELS = { code = 'Code', tools = 'Tools', ui = 'UI' }

-- 界面本身依赖它；禁用后界面无法打开，也就没有入口把它重新启用
local REQUIRED = { ['vv-utils'] = true }

local SLOW_MS = 10 -- 超过视为慢
local MID_MS = 3
local BAR_WIDTH = 24

require('vv-utils.hl').register('plugins.manager', {
  PackUILoaded = { link = 'String' },
  PackUIIdle = { link = 'Comment' },
  PackUIName = { link = 'Identifier' },
  PackUIDesc = { link = 'Comment' },
  PackUIDisabled = { link = 'NonText' },
  PackUIEager = { link = 'Function' },
  PackUILazy = { link = 'Comment' },
  PackUINumber = { link = 'Number' },
  PackUILabel = { link = 'Comment' },
  PackUIFast = { link = 'DiagnosticOk' },
  PackUIMid = { link = 'DiagnosticWarn' },
  PackUISlow = { link = 'DiagnosticError' },
  PackUINotice = { link = 'DiagnosticWarn' },
})

-- ---------------- 数据 ----------------

local function user_picks_path()
  local rel = 'lua/plugins/manager/user-picks.lua'
  for _, r in ipairs(vim.split(vim.o.rtp or '', ',')) do
    local p = r:gsub('[/\\]+$', '') .. '/' .. rel
    if vim.fn.filereadable(p) == 1 then return p end
  end
  return vim.fn.stdpath('config') .. '/' .. rel
end

local function load_picks()
  local ok, mod = pcall(require, 'plugins.manager.user-picks')
  if ok and type(mod) == 'table' then return vim.deepcopy(mod) end
  return {}
end

-- 只把 *禁用* 项写入文件，保持默认启用的语义
local function save_picks(picks)
  local lines = {
    '-- ================================',
    '-- 插件禁用表（:PluginManager 勾选后写入，可手动编辑）',
    '-- ================================',
    '-- 默认全部启用；只在此列出要 *禁用* 的插件：[id] = false',
    '-- 禁用后在新环境不会自动安装，已经安装的不会删除，删除 spec 文件后才会自动删除插件',
    '-- 已启用的无需列出。修改后重启 Neovim 生效',
    '',
    'return {',
  }
  -- 按 id 排序输出，保证文件稳定
  local ids = {}
  for id, v in pairs(picks) do
    if v == false then ids[#ids + 1] = id end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    lines[#lines + 1] = ('  [%q] = false,'):format(id)
  end
  lines[#lines + 1] = '}'
  vim.fn.writefile(lines, user_picks_path())
  package.loaded['plugins.manager.user-picks'] = nil
end

---@param picks table<string, boolean>
---@return boolean 禁用集合是否与本次会话启动时不同（改回原样就不再需要重启）
local function is_dirty(picks)
  local running = (_G.Pack and _G.Pack.picks) or {}
  for id, value in pairs(picks) do
    if value == false and running[id] ~= false then return true end
  end
  for id, value in pairs(running) do
    if value == false and picks[id] ~= false then return true end
  end
  return false
end

---@return table<string, { ms: number, lazy: boolean }> 插件 id → 本次会话的加载记录
local function load_records()
  local records = {}
  for _, plugin in ipairs((_G.PackStats or {}).plugins or {}) do
    records[plugin.name] = plugin
  end
  return records
end

---@param spec PackSpec
---@return boolean
local function is_lazy(spec)
  return not not (spec.event or spec.ft or spec.cmd or spec.keys or spec.lazy == 'manual')
end

---@param spec PackSpec
---@return string? 触发条件的简述；eager 插件为 nil
local function triggers(spec)
  local parts = {}
  local function add(label, value)
    if value == nil then return end
    if type(value) == 'function' then return parts[#parts + 1] end
    local list = type(value) == 'table' and value or { value }
    if #list > 0 then parts[#parts + 1] = label .. ' ' .. #list end
  end
  add('event', spec.event)
  add('ft', spec.ft)
  add('cmd', spec.cmd)
  if spec.keys then parts[#parts + 1] = 'keys' end
  if spec.lazy == 'manual' then parts[#parts + 1] = 'manual' end
  return #parts > 0 and table.concat(parts, ' · ') or nil
end

---@param ms number
---@return string
local function ms_hl(ms)
  if ms > SLOW_MS then return 'PackUISlow' end
  if ms > MID_MS then return 'PackUIMid' end
  return 'PackUIFast'
end

-- ---------------- 插件页 ----------------

---@param state table
---@param view VVUIViewHandle
---@return VVUIViewPage
local function plugins_page(state, view)
  local Rows = require('vv-utils.ui_rows')
  local records = load_records()
  local specs = (_G.Pack and _G.Pack.specs) or {}

  local by_category, order, seen = {}, {}, {}
  for _, spec in ipairs(specs) do
    local category = spec.category or 'tools'
    by_category[category] = by_category[category] or {}
    table.insert(by_category[category], spec)
  end
  -- 已知类别优先，未知类别按名称排在末尾
  for _, category in ipairs(CATEGORY_ORDER) do
    if by_category[category] then
      order[#order + 1], seen[category] = category, true
    end
  end
  local rest = vim.tbl_filter(function(category) return not seen[category] end, vim.tbl_keys(by_category))
  table.sort(rest)
  vim.list_extend(order, rest)

  local name_width = 0
  for _, spec in ipairs(specs) do
    name_width = math.max(name_width, vim.fn.strdisplaywidth(spec.id))
  end

  -- 描述列让出右侧的模式与耗时；窗口再窄也保留一小段描述
  local desc_width = math.max(12, vim.api.nvim_win_get_width(view.win) - name_width - 30)
  local enabled_total, loaded_total = 0, 0

  local sections = {}
  for _, category in ipairs(order) do
    local items, enabled_count = {}, 0
    for _, spec in ipairs(by_category[category]) do
      local enabled = state.picks[spec.id] ~= false
      local record = records[spec.id]
      local lazy = is_lazy(spec)
      if enabled then enabled_count = enabled_count + 1 end
      if record then loaded_total = loaded_total + 1 end

      local icon = record and { '● ', 'PackUILoaded' } or { '○ ', enabled and 'PackUIIdle' or 'PackUIDisabled' }
      local chunks = { icon }
      vim.list_extend(chunks, Rows.pad({ { spec.id, enabled and 'PackUIName' or 'PackUIDisabled' } }, name_width))
      chunks[#chunks + 1] = { '  ' }
      vim.list_extend(chunks, Rows.truncate({ { spec.desc or '', enabled and 'PackUIDesc' or 'PackUIDisabled' } }, desc_width))

      local tail = {}
      if not enabled then
        tail[#tail + 1] = { 'disabled', 'PackUIDisabled' }
      else
        if record then
          tail[#tail + 1] = { ('%.2f ms'):format(record.ms), ms_hl(record.ms) }
          tail[#tail + 1] = { '  ' }
        end
        tail[#tail + 1] = { lazy and 'lazy ' or 'eager', lazy and 'PackUILazy' or 'PackUIEager' }
      end
      tail[#tail + 1] = { ' ' }

      items[#items + 1] = {
        id = spec.id,
        data = spec,
        row = { chunks = chunks, virt_text = tail, virt_text_pos = 'right_align' },
        detail = function()
          local source = spec.dir or (type(spec.url) == 'table' and spec.url.src or spec.url) or '-'
          local status = not enabled and 'Disabled'
            or record and ('Loaded in %.2f ms'):format(record.ms)
            or 'Not loaded'
          local props = {
            { { { 'Status', 'VVViewDetailKey' } }, { { status, 'VVViewDetailValue' } } },
            { { { 'Source', 'VVViewDetailKey' } }, { { source, 'VVViewDetailValue' } } },
            { { { 'Load', 'VVViewDetailKey' } }, { { triggers(spec) or 'At startup', 'VVViewDetailValue' } } },
          }
          if spec.dependencies and #spec.dependencies > 0 then
            local names = vim.tbl_map(function(dep)
              return (type(dep) == 'table' and dep.src or dep):match('[^/]+$')
            end, spec.dependencies)
            props[#props + 1] = {
              { { 'Deps', 'VVViewDetailKey' } },
              { { table.concat(names, ', '), 'VVViewDetailValue' } },
            }
          end
          if spec.desc and vim.fn.strdisplaywidth(spec.desc) > desc_width then
            table.insert(props, 1, { { { 'Desc', 'VVViewDetailKey' } }, { { spec.desc, 'VVViewDetailValue' } } })
          end
          return Rows.table(props)
        end,
      }
    end

    enabled_total = enabled_total + enabled_count
    sections[#sections + 1] = {
      id = 'category:' .. category,
      title = CATEGORY_LABELS[category] or category,
      count = enabled_count == #items and #items or (enabled_count .. '/' .. #items),
      items = items,
    }
  end

  local summary = {
    { 'Plugins ', 'PackUILabel' }, { tostring(#specs), 'PackUINumber' },
    { '    Enabled ', 'PackUILabel' }, { tostring(enabled_total), 'PackUINumber' },
    { '    Loaded ', 'PackUILabel' }, { tostring(loaded_total), 'PackUINumber' },
  }
  if is_dirty(state.picks) then
    summary[#summary + 1] = { '    Restart Neovim to apply changes', 'PackUINotice' }
  end

  return { header = { summary }, sections = sections, empty = { { 'No plugins to manage', 'PackUILabel' } } }
end

---@param state table
---@param view VVUIViewHandle
---@param item VVUIViewItem?
local function toggle_enabled(state, view, item)
  if not item then return end
  local id = item.id
  if REQUIRED[id] and state.picks[id] ~= false then
    vim.notify(('%s is required by the plugin manager and cannot be disabled'):format(id), vim.log.levels.WARN)
    return
  end

  -- enabled(nil) → false；disabled(false) → nil（从文件里清掉）
  if state.picks[id] == false then state.picks[id] = nil else state.picks[id] = false end
  save_picks(state.picks)
  view.refresh()
end

-- ---------------- 耗时页 ----------------

---@param state table
---@return VVUIViewPage
local function stats_page(state)
  local Rows = require('vv-utils.ui_rows')
  local stats = _G.PackStats or {}
  local all = stats.plugins or {}

  local eager_count, lazy_count, eager_ms, lazy_ms, slowest = 0, 0, 0, 0, 0
  for _, plugin in ipairs(all) do
    local ms = plugin.ms or 0
    slowest = math.max(slowest, ms)
    if plugin.lazy then
      lazy_count, lazy_ms = lazy_count + 1, lazy_ms + ms
    else
      eager_count, eager_ms = eager_count + 1, eager_ms + ms
    end
  end

  local plugins = vim.tbl_filter(function(plugin)
    return not state.eager_only or not plugin.lazy
  end, all)
  if state.sort == 'name' then
    table.sort(plugins, function(a, b) return (a.name or '') < (b.name or '') end)
  else
    table.sort(plugins, function(a, b) return (a.ms or 0) > (b.ms or 0) end)
  end

  local function metric(label, value, unit)
    return { { label .. ' ', 'PackUILabel' }, { value, 'PackUINumber' }, { unit and (' ' .. unit) or '', 'PackUILabel' } }
  end
  local function join(groups)
    local chunks = {}
    for index, group in ipairs(groups) do
      if index > 1 then chunks[#chunks + 1] = { '    ' } end
      vim.list_extend(chunks, group)
    end
    return chunks
  end

  local header = {
    join({
      metric('Startup', ('%.2f'):format(require('pack.stats').startup_ms()), 'ms'),
      metric('Dispatch', ('%.2f'):format(stats.total_ms or 0), 'ms'),
      metric('vim.pack', ('%.2f'):format(stats.add_ms or 0), 'ms'),
      metric('Loaded', ('%d/%d'):format(#all, stats.registered or 0)),
    }),
    join({
      { { '▲ eager ', 'PackUIEager' }, { tostring(eager_count), 'PackUINumber' },
        { ' · ', 'PackUILabel' }, { ('%.2f ms'):format(eager_ms), ms_hl(eager_ms) } },
      { { '▽ lazy ', 'PackUILazy' }, { tostring(lazy_count), 'PackUINumber' },
        { ' · ', 'PackUILabel' }, { ('%.2f ms'):format(lazy_ms), 'PackUILazy' } },
    }),
    join({
      { { 'Sort ', 'PackUILabel' }, { state.sort == 'name' and 'Name' or 'Time', 'PackUINumber' } },
      { { 'Scope ', 'PackUILabel' }, { state.eager_only and 'Eager only' or 'All', 'PackUINumber' } },
    }),
  }

  local cells = {}
  for index, plugin in ipairs(plugins) do
    local ms = plugin.ms or 0
    cells[index] = {
      { { plugin.name or '?', 'PackUIName' } },
      Rows.bar(slowest > 0 and ms / slowest or 0, BAR_WIDTH, { done_hl = ms_hl(ms), todo_char = '─' }),
      { { ('%.2f ms'):format(ms), ms_hl(ms) } },
      { { plugin.lazy and 'lazy' or 'eager', plugin.lazy and 'PackUILazy' or 'PackUIEager' } },
    }
  end

  local items = {}
  for index, chunks in ipairs(Rows.table(cells, { align = { [3] = 'right' } })) do
    items[index] = { id = plugins[index].name or tostring(index), row = chunks }
  end

  return {
    header = header,
    sections = { { id = 'loaded', title = 'Loaded plugins', items = items } },
    empty = { { 'No load records this session', 'PackUILabel' } },
  }
end

-- ---------------- 入口 ----------------

local current ---@type VVUIViewHandle?

---@param tab? 'plugins'|'stats' @default 'plugins'
function M.open(tab)
  tab = tab or 'plugins'
  if current and current.is_open() then
    current.set_tab(tab)
    vim.api.nvim_set_current_win(current.win)
    return
  end

  local state = { picks = load_picks(), sort = 'ms', eager_only = false }

  current = require('vv-utils.ui_view').open({
    brand = 'Pack',
    filetype = 'PluginManager',
    desc_prefix = 'pack',
    tab = tab,
    tabs = {
      { id = 'plugins', label = 'Plugins', key = '1' },
      { id = 'stats', label = 'Stats', key = '2' },
    },
    page = function(view)
      if view.tab() == 'stats' then return stats_page(state) end
      return plugins_page(state, view)
    end,
    actions = {
      {
        key = { 'x', '<Space>' },
        desc = 'Toggle',
        tab = 'plugins',
        run = function(view, item) toggle_enabled(state, view, item) end,
      },
      { key = '<CR>', desc = 'Details', tab = 'plugins', run = function(view) view.toggle() end },
      {
        key = 's',
        desc = 'Sort',
        tab = 'stats',
        run = function(view)
          state.sort = state.sort == 'ms' and 'name' or 'ms'
          view.refresh()
        end,
      },
      {
        key = 'e',
        desc = 'Eager only',
        tab = 'stats',
        run = function(view)
          state.eager_only = not state.eager_only
          view.refresh()
        end,
      },
      { key = '<Tab>', desc = 'Switch', run = function(view) view.cycle_tab(1) end },
    },
    on_close = function() current = nil end,
  })
end

return M
