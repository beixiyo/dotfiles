-- Nvim 0.13+ 多光标操作指南
--
-- VS Code 风格：
--   <C-d>       为当前单词或单行字符选区逐次添加下一处匹配（到末尾回绕）
--   <C-S-l>     为当前单词或单行选区添加全部匹配
--   <C-Up/Down> 在相邻行同列添加光标；<A-LeftMouse> 在点击处添加光标
--   文本匹配会先把主光标归一到匹配起点，确保所有光标位于同一相对位置
--
-- 原生操作：
--   q= / 1q= / 2q=  切换 / 强制开启 / 强制关闭逐光标跟随
--   <Esc> / <C-l>    清除当前 buffer 的多光标；gQ 恢复刚清除的光标
--   [C / ]C          跳到上一个 / 下一个光标，同时在原位置留下光标
--
-- 适配层只负责“找位置 / 加光标”；实际编辑和生命周期仍由 Nvim 管理

local map = require('config.keymaps.helpers').map

local M = {}

local multicursor_ns = vim.api.nvim_create_namespace('nvim.multicursor')
local generations = {}
local selections = {}

---清除指定 buffer 的多光标，并保留原生 gQ 恢复快照
---@param buf? integer 默认当前 buffer
function M.clear(buf)
  buf = buf and buf ~= 0 and buf or vim.api.nvim_get_current_buf()
  generations[buf] = (generations[buf] or 0) + 1
  selections[buf] = nil

  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, multicursor_ns, 0, -1)
  end
end

---在当前匹配之后查找下一个完全相同的文本
---@param lines string[]
---@param selection { text: string, start: { row: integer, col: integer }, finish: { row: integer, col: integer } }
---@return { start: { row: integer, col: integer }, finish: { row: integer, col: integer } }?
function M.find_next_match(lines, selection)
  if selection.text == '' then
    return nil
  end

  for row = selection.start.row, #lines do
    local from = row == selection.start.row and selection.finish.col + 1 or 1
    local start_col, end_col = lines[row]:find(selection.text, from, true)

    if start_col then
      return {
        start = { row = row, col = start_col - 1 },
        finish = { row = row, col = end_col },
      }
    end
  end
end

local function get_visual_selection()
  if vim.fn.mode():sub(1, 1) ~= 'v' then
    return nil
  end

  local anchor = vim.fn.getpos('v')
  local cursor = vim.fn.getpos('.')
  if anchor[2] ~= cursor[2] or anchor[4] ~= 0 or cursor[4] ~= 0 then
    return nil
  end

  local start_col = math.min(anchor[3], cursor[3])
  -- 原生提取负责正反向、selection 选项及 Unicode 完整字符
  local text = vim.fn.getregion(anchor, cursor, { type = 'v' })[1] or ''
  if text == '' then
    return nil
  end

  return {
    text = text,
    start = { row = anchor[2], col = start_col - 1 },
    finish = { row = anchor[2], col = start_col - 1 + #text },
  }
end

local function get_current_word()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local word = vim.fn.expand('<cword>')
  if word == '' then
    return nil
  end

  local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]
  local search_from = 1
  while true do
    local start_col, end_col = line:find(word, search_from, true)
    if not start_col then
      return nil
    end

    if start_col - 1 <= col and col < end_col then
      return {
        text = word,
        start = { row = row, col = start_col - 1 },
        finish = { row = row, col = end_col },
      }
    end

    search_from = start_col + 1
  end
end

local function get_selection()
  if vim.fn.mode() ~= 'n' then
    return get_visual_selection()
  end

  local saved = selections[vim.api.nvim_get_current_buf()]
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))

  if saved and saved.tick == vim.api.nvim_buf_get_changedtick(0)
    and saved.start.row == row and saved.start.col == col
    and #vim.api.nvim_buf_get_extmarks(0, multicursor_ns, 0, -1, { limit = 1 }) > 0 then
    return saved
  end

  return get_current_word()
end

local function normalize_primary_cursor(selection)
  if vim.fn.mode():sub(1, 1) == 'v' then
    vim.cmd.normal({ args = { '\27' }, bang = true })
  end

  vim.api.nvim_win_set_cursor(0, { selection.start.row, selection.start.col })
  selection.tick = vim.api.nvim_buf_get_changedtick(0)
  selections[vim.api.nvim_get_current_buf()] = selection
end

local function cursor_positions()
  local positions = {}

  for _, cursor in ipairs(vim.api.nvim_buf_get_extmarks(0, multicursor_ns, 0, -1, {})) do
    positions[cursor[2] + 1 .. ':' .. cursor[3]] = true
  end

  return positions
end

local function add_cursor(pos)
  local buf = vim.api.nvim_get_current_buf()
  generations[buf] = (generations[buf] or 0) + 1
  local before = #vim.api.nvim_buf_get_extmarks(0, multicursor_ns, 0, -1, { limit = 1 })
  vim.api.nvim_mcursor(0, pos)
  local after = #vim.api.nvim_buf_get_extmarks(0, multicursor_ns, 0, -1, { limit = 1 })

  if before == 0 and after == 1 then
    -- 当前调用已在 Normal 模式；同步启用，避免延迟命令落到其他窗口或新会话
    vim.cmd('normal! 1q=')
  end
end

local function add_next_match()
  local selection = get_selection()
  if not selection then
    return
  end

  normalize_primary_cursor(selection)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local occupied = cursor_positions()

  occupied[selection.start.row .. ':' .. selection.start.col] = true
  local probe = selection
  local wrapped = false

  while true do
    local candidate = M.find_next_match(lines, probe)
    if not candidate then
      if wrapped then return end
      wrapped = true
      probe = { text = selection.text, start = { row = 1, col = 0 }, finish = { row = 1, col = 0 } }
    else
      if wrapped and (candidate.start.row > selection.start.row
        or (candidate.start.row == selection.start.row and candidate.start.col >= selection.start.col)) then
        return
      end

      local key = candidate.start.row .. ':' .. candidate.start.col
      if not occupied[key] then
        add_cursor({ candidate.start.row, candidate.start.col })
        return
      end

      probe = vim.tbl_extend('force', candidate, { text = selection.text })
    end
  end
end

local function add_all_matches()
  local selection = get_selection()
  if not selection then
    return
  end

  normalize_primary_cursor(selection)
  for row, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    local from = 1

    while true do
      local start_col, end_col = line:find(selection.text, from, true)
      if not start_col then
        break
      end

      local pos = { row = row, col = start_col - 1 }
      if not (pos.row == selection.start.row and pos.col == selection.start.col) then
        add_cursor({ pos.row, pos.col })
      end
      from = end_col + 1
    end
  end
end

local function add_vertical_cursor(delta)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local column = vim.fn.virtcol('.', true)[1]

  -- 主光标会留在原处；连续按方向键时从该方向最远的已有光标继续延伸
  for _, cursor in ipairs(vim.api.nvim_buf_get_extmarks(0, multicursor_ns, 0, -1, {})) do
    local cursor_row = cursor[2] + 1
    if (delta > 0 and cursor_row > row) or (delta < 0 and cursor_row < row) then
      row = cursor_row
    end
  end

  local target_row = row + delta
  local line_count = vim.api.nvim_buf_line_count(0)
  if target_row < 1 or target_row > line_count then
    return
  end

  -- 转换显示列为字符起始字节；短行停在末字符，空行使用第 0 列
  local col = vim.fn.virtcol2col(0, target_row, column)
  add_cursor({ target_row, math.max(0, col - 1) })
end

local function add_cursor_at_mouse()
  local pos = vim.fn.getmousepos()
  if not pos or pos.winid == 0 or pos.line < 1 then
    return
  end

  if vim.api.nvim_get_current_win() ~= pos.winid then
    vim.api.nvim_set_current_win(pos.winid)
  end
  add_cursor({ pos.line, math.max(0, pos.column - 1) })
end

-- 0.12 保留原有按键语义；不安装会调用不存在 API 的映射
if not vim.api.nvim_mcursor then
  return M
end

vim.api.nvim_create_autocmd('BufWipeout', {
  group = vim.api.nvim_create_augroup('config_multicursor', { clear = true }),
  callback = function(event)
    generations[event.buf] = nil
    selections[event.buf] = nil
  end,
})

map({ 'n', 'x' }, '<C-d>', add_next_match, { desc = 'Multicursor: add next match' })
map({ 'n', 'x' }, '<C-S-l>', add_all_matches, { desc = 'Multicursor: add all matches' })
map('n', '<C-Up>', function() add_vertical_cursor(-1) end, { desc = 'Multicursor: add cursor above' })
map('n', '<C-Down>', function() add_vertical_cursor(1) end, { desc = 'Multicursor: add cursor below' })
map('n', '<A-LeftMouse>', add_cursor_at_mouse, { desc = 'Multicursor: add cursor at mouse' })
map({ 'i', 'x' }, '<Esc>', function()
  local buf = vim.api.nvim_get_current_buf()
  local generation = generations[buf]
  local cursors = vim.api.nvim_buf_get_extmarks(buf, multicursor_ns, 0, -1, {})

  -- 等原生插入提交完成；只清理原 buffer 中没有被替换或扩展的那次会话
  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(buf) and generations[buf] == generation then
      local current = vim.api.nvim_buf_get_extmarks(buf, multicursor_ns, 0, -1, {})
      local ids = function(marks)
        local result = vim.tbl_map(function(mark) return mark[1] end, marks)
        table.sort(result)
        return result
      end
      if vim.deep_equal(ids(current), ids(cursors)) then M.clear(buf) end
    end
  end, 0)
  return '<Esc>'
end, { desc = 'Multicursor: clear', expr = true })

return M
