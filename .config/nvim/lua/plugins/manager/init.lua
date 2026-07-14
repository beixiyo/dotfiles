-- ================================
-- :PluginManager GUI —— 浮窗多选界面
-- 数据源：_G.Pack.specs（启动期 pack 写入）
-- 状态源：user-picks.lua（默认全启用，记录禁用集合）
-- ================================

local M = {}

local CONFIG = {
  separator_len = 60,
  category_order = { 'code', 'tools', 'ui' },
  category_labels = { code = '代码', tools = '工具', ui = '界面' },
  width_ratio = 0.7,
  height_ratio = 0.9,
}

local ns = vim.api.nvim_create_namespace('plugin_manager2')

local function user_picks_path()
  local rel = 'lua/plugins/manager/user-picks.lua'
  for _, r in ipairs(vim.split(vim.o.rtp or '', ',')) do
    local p = r:gsub('[/\\]+$', '') .. '/' .. rel
    if vim.fn.filereadable(p) == 1 then return p end
  end
  return vim.fn.stdpath('config') .. '/' .. rel
end

local function get_specs()
  return (_G.Pack and _G.Pack.specs) or {}
end

local function load_picks()
  local ok, mod = pcall(require, 'plugins.manager.user-picks')
  if ok and type(mod) == 'table' then return mod end
  return {}
end

-- 只把 *禁用* 项写入文件，保持默认启用的语义
local function save_picks(picks)
  local path = user_picks_path()
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
    if v == false then table.insert(ids, id) end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    lines[#lines + 1] = ('  [%q] = false,'):format(id)
  end
  lines[#lines + 1] = '}'
  vim.fn.writefile(lines, path)
  package.loaded['plugins.manager.user-picks'] = nil
end

local function line_for(spec, picks)
  local enabled = picks[spec.id] ~= false
  local mark = enabled and '[✓]' or '[ ]'
  return ('%s %-20s %s'):format(mark, spec.id, spec.desc or '')
end

local function build_content(specs, picks)
  local lines = {
    ' Plugin Manager - 可选插件管理（Enter/x 切换，q 关闭）',
    string.rep('─', CONFIG.separator_len),
  }
  local id_by_line = {}

  local by_cat = {}
  for _, s in ipairs(specs) do
    local c = s.category or 'tools'
    by_cat[c] = by_cat[c] or {}
    table.insert(by_cat[c], s)
  end

  -- 已知类别优先，未知类别 append 到末尾
  local ordered = {}
  local seen = {}
  for _, c in ipairs(CONFIG.category_order) do
    if by_cat[c] then
      table.insert(ordered, c); seen[c] = true
    end
  end
  for c, _ in pairs(by_cat) do
    if not seen[c] then table.insert(ordered, c) end
  end

  for _, cat in ipairs(ordered) do
    local list = by_cat[cat]
    lines[#lines + 1] = ''
    local label = CONFIG.category_labels[cat] or cat
    lines[#lines + 1] = (' %s (%d)'):format(label, #list)
    for _, s in ipairs(list) do
      lines[#lines + 1] = line_for(s, picks)
      id_by_line[#lines] = s.id
    end
  end

  return lines, id_by_line
end

local function calc_win(lines)
  local width = math.floor(vim.o.columns * CONFIG.width_ratio)
  local height = math.min(#lines + 2, math.floor(vim.o.lines * CONFIG.height_ratio))
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)
  return { width = width, height = height, row = row, col = col }
end

local function apply_hl(buf, id_by_line)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  local function link(name, to) pcall(vim.api.nvim_set_hl, 0, name, { link = to }) end
  link('PluginManagerTitle', 'Title')
  link('PluginManagerSeparator', 'Comment')
  link('PluginManagerSection', 'Constant')
  link('PluginManagerMarkOn', 'DiffAdded')
  link('PluginManagerMarkOff', 'Comment')
  link('PluginManagerId', 'Identifier')

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for i, line in ipairs(lines) do
    local lnum = i - 1
    if i == 1 then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { end_row = lnum + 1, hl_group = 'PluginManagerTitle' })
    elseif i == 2 then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { end_row = lnum + 1, hl_group = 'PluginManagerSeparator' })
    elseif not id_by_line[i] and line:match('^ %S') then
      vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { end_row = lnum + 1, hl_group = 'PluginManagerSection' })
    else
      local id = id_by_line[i]
      if type(id) == 'string' then
        local group = line:find('✓', 1, true) and 'PluginManagerMarkOn' or 'PluginManagerMarkOff'
        vim.api.nvim_buf_set_extmark(buf, ns, lnum, 0, { end_col = 3, hl_group = group })
        local s, e = line:find(id, 1, true)
        if s and e then
          vim.api.nvim_buf_set_extmark(buf, ns, lnum, s - 1, { end_col = e, hl_group = 'PluginManagerId' })
        end
      end
    end
  end
end

local function setup_keymaps(buf, win, toggle)
  local opts = { noremap = true, silent = true, buffer = buf }
  vim.keymap.set('n', '<CR>', toggle, opts)
  vim.keymap.set('n', 'x', toggle, opts)
  local close = function() vim.api.nvim_win_close(win, true) end
  vim.keymap.set('n', 'q', close, opts)
  vim.keymap.set('n', '<Esc>', close, opts)
end

function M.open()
  local specs = get_specs()
  if #specs == 0 then
    vim.notify('[pack] 无可管理 spec（_G.Pack.specs 为空）', vim.log.levels.WARN)
    return
  end
  local picks = load_picks()
  local id_to_spec = {}
  for _, s in ipairs(specs) do id_to_spec[s.id] = s end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].filetype = 'PluginManager'

  local lines, id_by_line = build_content(specs, picks)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.b[buf].plugin_manager_ids = id_by_line

  apply_hl(buf, id_by_line)

  local wc = calc_win(lines)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    row = wc.row, col = wc.col, width = wc.width, height = wc.height,
    style = 'minimal', border = 'rounded',
    title = ' Plugin Manager ', title_pos = 'center',
  })

  local function toggle()
    local cur = vim.api.nvim_win_get_cursor(win)[1]
    local id = id_by_line[cur]
    if not id then return end

    -- 三态规整：enabled(nil or true) → false；disabled(false) → nil（清掉）
    if picks[id] == false then picks[id] = nil else picks[id] = false end

    local spec = id_to_spec[id]
    if not spec then return end
    vim.api.nvim_buf_set_lines(buf, cur - 1, cur, false, { line_for(spec, picks) })
    save_picks(picks)
    apply_hl(buf, id_by_line)
  end

  setup_keymaps(buf, win, toggle)
end

return M
