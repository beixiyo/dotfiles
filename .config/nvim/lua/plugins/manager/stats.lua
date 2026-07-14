-- ================================
-- :PackStats GUI —— 浮窗性能分析界面
-- 数据源：_G.PackStats（由 pack/stats.lua 在启动期 wrap loader.load 写入）
-- 键位：q/Esc 关闭；s 按耗时排序；n 按名称排序；e 仅看 eager；a 看全部
-- ================================

local M = {}

local CONFIG = {
  width_ratio   = 0.7,
  height_ratio  = 0.85,
  slow_ms       = 10,     -- 红色阈值（超过视为慢）
  mid_ms        = 3,      -- 黄色阈值（3-10 ms 视为中）
  separator_len = 68,
}

local ns = vim.api.nvim_create_namespace('pack_stats')

-- 四个核心数字各用不同颜色构成彩色仪表盘；eager/lazy 用暖/冷对比
require('vv-utils.hl').register('pack_stats.hl', {
  PackStatsLabel     = { link = 'Comment' },
  PackStatsUnit      = { link = 'NonText' },
  PackStatsSep       = { link = 'NonText' },

  PackStatsDotTotal  = { link = 'DiagnosticInfo' },
  PackStatsDotAdd    = { link = 'DiagnosticHint' },
  PackStatsDotReg    = { link = 'Constant' },
  PackStatsDotLoaded = { link = 'String' },
  PackStatsNumTotal  = { link = 'Function' },
  PackStatsNumAdd    = { link = 'Special' },
  PackStatsNumReg    = { link = 'Number' },
  PackStatsNumLoaded = { link = 'String' },

  PackStatsEager     = { link = 'Function' },
  PackStatsLazy      = { link = 'Comment' },

  PackStatsKey       = { link = 'Special' },
  PackStatsKeyDesc   = { link = 'Comment' },

  PackStatsHeader    = { link = 'Title' },

  PackStatsFast      = { link = 'DiagnosticOk' },
  PackStatsMid       = { link = 'DiagnosticWarn' },
  PackStatsSlow      = { link = 'DiagnosticError' },
})

-- ---------------- 数据收集 ----------------
-- 过滤/排序状态：挂 buffer-local 而非模块级，避免多实例串扰
-- sort: 'ms' | 'name'    filter: 'all' | 'eager'

local function collect(sort, filter)
  local s = _G.PackStats or {}
  local plugins = vim.deepcopy(s.plugins or {})

  if filter == 'eager' then
    plugins = vim.tbl_filter(function(p) return not p.lazy end, plugins)
  end

  if sort == 'name' then
    table.sort(plugins, function(a, b) return (a.name or '') < (b.name or '') end)
  else
    table.sort(plugins, function(a, b) return (a.ms or 0) > (b.ms or 0) end)
  end

  local eager_n, lazy_n, eager_ms, lazy_ms = 0, 0, 0, 0
  for _, p in ipairs(s.plugins or {}) do
    if p.lazy then
      lazy_n = lazy_n + 1
      lazy_ms = lazy_ms + (p.ms or 0)
    else
      eager_n = eager_n + 1
      eager_ms = eager_ms + (p.ms or 0)
    end
  end

  return {
    total_ms   = s.total_ms or 0,
    add_ms     = s.add_ms or 0,
    registered = s.registered or 0,
    loaded     = #(s.plugins or {}),
    eager_n    = eager_n, eager_ms = eager_ms,
    lazy_n     = lazy_n,  lazy_ms  = lazy_ms,
    plugins    = plugins,
  }
end

-- ---------------- 分段渲染 ----------------
-- 每行由 {text, hl?} 的 chunk 列表拼成，同时记录每段精确 byte 偏移
-- 这样同一行内可以对 label / 数字 / 单位 各自独立染色

---@alias PackChunk { [1]: string, [2]?: string }

---@param chunks PackChunk[]
local function chunks_to_line(chunks)
  local text, marks, off = '', {}, 0
  for _, c in ipairs(chunks) do
    local s, hl = c[1] or '', c[2]
    text = text .. s
    if hl and #s > 0 then
      marks[#marks + 1] = { col = off, end_col = off + #s, hl = hl }
    end
    off = off + #s
  end
  return text, marks
end

local function ms_hl(ms)
  if ms > CONFIG.slow_ms then return 'PackStatsSlow' end
  if ms > CONFIG.mid_ms  then return 'PackStatsMid'  end
  return 'PackStatsFast'
end

local function build_content(data, sort, filter)
  local lines, line_marks, plugin_line = {}, {}, {}

  local function push(chunks)
    local text, marks = chunks_to_line(chunks)
    lines[#lines + 1] = text
    if #marks > 0 then line_marks[#lines] = marks end
  end

  -- 行 1：四个核心数字，各带彩色圆点
  push {
    { '  ' },
    { '● ',                                    'PackStatsDotTotal'  },
    { '总耗时 ',                               'PackStatsLabel'     },
    { string.format('%.2f', data.total_ms),    'PackStatsNumTotal'  },
    { ' ms',                                   'PackStatsUnit'      },
    { '    ' },
    { '● ',                                    'PackStatsDotAdd'    },
    { 'vim.pack ',                             'PackStatsLabel'     },
    { string.format('%.2f', data.add_ms),      'PackStatsNumAdd'    },
    { ' ms',                                   'PackStatsUnit'      },
    { '    ' },
    { '● ',                                    'PackStatsDotReg'    },
    { '注册 ',                                 'PackStatsLabel'     },
    { tostring(data.registered),               'PackStatsNumReg'    },
    { '    ' },
    { '● ',                                    'PackStatsDotLoaded' },
    { '已加载 ',                               'PackStatsLabel'     },
    { tostring(data.loaded),                   'PackStatsNumLoaded' },
  }

  -- 行 2：eager / lazy 对比（▲/▽ + 数字按快慢阈值染色）
  push {
    { '  ' },
    { '▲ ',                                    'PackStatsEager' },
    { 'eager ',                                'PackStatsLabel' },
    { tostring(data.eager_n),                  'PackStatsEager' },
    { ' 个 / ',                                'PackStatsUnit'  },
    { string.format('%.2f', data.eager_ms),    ms_hl(data.eager_ms) },
    { ' ms',                                   'PackStatsUnit'  },
    { '      ' },
    { '▽ ',                                    'PackStatsLazy'  },
    { 'lazy ',                                 'PackStatsLabel' },
    { tostring(data.lazy_n),                   'PackStatsLazy'  },
    { ' 个 / ',                                'PackStatsUnit'  },
    { string.format('%.2f', data.lazy_ms),     'PackStatsLazy'  },
    { ' ms',                                   'PackStatsUnit'  },
  }

  -- 行 3：当前状态 + 键位提示
  local sort_text   = sort == 'name'     and '名称'     or '耗时'
  local filter_text = filter == 'eager'  and '仅 eager' or '全部'
  push {
    { '  ' },
    { '排序 ',    'PackStatsLabel'    },
    { sort_text,  'PackStatsNumTotal' },
    { '   ' },
    { '过滤 ',    'PackStatsLabel'    },
    { filter_text,'PackStatsNumAdd'   },
    { '      ' },
    { '[s]', 'PackStatsKey' }, { ' 耗时  ',  'PackStatsKeyDesc' },
    { '[n]', 'PackStatsKey' }, { ' 名称  ',  'PackStatsKeyDesc' },
    { '[e]', 'PackStatsKey' }, { ' eager  ', 'PackStatsKeyDesc' },
    { '[a]', 'PackStatsKey' }, { ' 全部  ',  'PackStatsKeyDesc' },
    { '[q]', 'PackStatsKey' }, { ' 关闭',    'PackStatsKeyDesc' },
  }

  push {{ string.rep('─', CONFIG.separator_len), 'PackStatsSep' }}

  push {
    { '  ' },
    { ('%-34s'):format('插件'),    'PackStatsHeader' },
    { ' ' },
    { ('%10s'):format('耗时 ms'),  'PackStatsHeader' },
    { '   ' },
    { '模式',                      'PackStatsHeader' },
  }

  push {{ string.rep('─', CONFIG.separator_len), 'PackStatsSep' }}

  for _, p in ipairs(data.plugins) do
    local ms = p.ms or 0
    local mode_hl = p.lazy and 'PackStatsLazy' or 'PackStatsEager'
    push {
      { '  ' },
      { ('%-34s'):format(p.name or '?'), 'PackStatsLabel' },
      { ' ' },
      { ('%10.2f'):format(ms),           ms_hl(ms)        },
      { '   ' },
      { p.lazy and 'lazy' or 'eager',    mode_hl          },
    }
    plugin_line[#lines] = p
  end

  return lines, plugin_line, line_marks
end

local function apply_hl(buf, line_marks)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for row, marks in pairs(line_marks) do
    for _, m in ipairs(marks) do
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, row - 1, m.col, {
        end_col = m.end_col, hl_group = m.hl,
      })
    end
  end
end

local function render(buf, sort, filter)
  local data = collect(sort, filter)
  local lines, plugin_line, line_marks = build_content(data, sort, filter)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.b[buf].pack_stats_plugin_line = plugin_line
  apply_hl(buf, line_marks)
end

function M.open()
  if not _G.PackStats then
    vim.notify('[pack] _G.PackStats 不存在（stats 未初始化）', vim.log.levels.WARN)
    return
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'PackStats'

  local state = { sort = 'ms', filter = 'all' }
  render(buf, state.sort, state.filter)

  local width = math.floor(vim.o.columns * CONFIG.width_ratio)
  local height = math.min(
    #vim.api.nvim_buf_get_lines(buf, 0, -1, false) + 2,
    math.floor(vim.o.lines * CONFIG.height_ratio)
  )
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, true, {
    relative  = 'editor',
    row       = row, col = col, width = width, height = height,
    style     = 'minimal',
    border    = 'rounded',
    title     = ' ⚡ Pack Stats ',
    title_pos = 'center',
  })

  local opts = { noremap = true, silent = true, buffer = buf }
  local close = function()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end
  vim.keymap.set('n', 'q', close, opts)
  vim.keymap.set('n', '<Esc>', close, opts)

  vim.keymap.set('n', 's', function() state.sort = 'ms';      render(buf, state.sort, state.filter) end, opts)
  vim.keymap.set('n', 'n', function() state.sort = 'name';    render(buf, state.sort, state.filter) end, opts)
  vim.keymap.set('n', 'e', function() state.filter = 'eager'; render(buf, state.sort, state.filter) end, opts)
  vim.keymap.set('n', 'a', function() state.filter = 'all';   render(buf, state.sort, state.filter) end, opts)
end

return M
