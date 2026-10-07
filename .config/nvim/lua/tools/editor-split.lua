-- 编辑区定向查看：复用相邻文件窗口，或在可配置的行列上限内创建分屏
-- 不移动标签、不删除 buffer，也不接管侧边栏、终端和浮窗
local M = {}

---仅普通文件与空白编辑窗口参与布局；工具窗口和独立 diff 工作区保持原样
---@param win integer
---@return boolean
local function is_editor(win)
  local config = vim.api.nvim_win_get_config(win)
  local buf = vim.api.nvim_win_get_buf(win)
  return config.relative == '' and not config.external
    and not vim.wo[win].winfixbuf and not vim.wo[win].diff
    and not vim.w[win].vv_bufferline_ignore
    and vim.bo[buf].buftype == '' and vim.bo[buf].buflisted
end

---用实际屏幕位置寻找有交叠的另一侧，跳过工具窗口；等距离时优先上方／左方
---@param source integer
---@param wins integer[]
---@param axis 'horizontal'|'vertical'
---@return {forward?: integer, backward?: integer}
local function opposite(source, wins, axis)
  local along = axis == 'vertical' and 2 or 1
  local across = 3 - along
  local function rect(win)
    local pos = vim.api.nvim_win_get_position(win)
    local size = { vim.api.nvim_win_get_height(win), vim.api.nvim_win_get_width(win) }
    return { pos = pos, size = size }
  end

  local origin = rect(source)
  local candidates = {}
  for _, win in ipairs(wins) do
    if win ~= source then
      local other = rect(win)
      local overlaps = math.max(origin.pos[across], other.pos[across])
        < math.min(origin.pos[across] + origin.size[across], other.pos[across] + other.size[across])
      local distance, side
      if other.pos[along] >= origin.pos[along] + origin.size[along] then
        distance = other.pos[along] - origin.pos[along] - origin.size[along]
        side = 'forward'
      elseif origin.pos[along] >= other.pos[along] + other.size[along] then
        distance = origin.pos[along] - other.pos[along] - other.size[along]
        side = 'backward'
      end
      if overlaps and distance then
        candidates[#candidates + 1] = { win = win, distance = distance, pos = other.pos, side = side }
      end
    end
  end

  table.sort(candidates, function(a, b)
    if a.distance ~= b.distance then return a.distance < b.distance end
    if a.pos[1] ~= b.pos[1] then return a.pos[1] < b.pos[1] end
    return a.pos[2] < b.pos[2]
  end)
  local targets = {}
  for _, candidate in ipairs(candidates) do
    targets[candidate.side] = targets[candidate.side] or candidate.win
  end
  return targets
end

---忽略工具窗口后计算布局容量，并模拟在 source 上分屏；同时约束行数、列数而非仅总数
---@param node table winlayout() 节点
---@param editors table<integer, boolean>
---@param source integer
---@param axis 'horizontal'|'vertical'
---@return integer columns
---@return integer rows
local function dimensions(node, editors, source, axis)
  if node[1] == 'leaf' then
    if not editors[node[2]] then return 0, 0 end
    if node[2] ~= source then return 1, 1 end
    if axis == 'vertical' then return 2, 1 end
    return 1, 2
  end

  local columns, rows = 0, 0
  for _, child in ipairs(node[2]) do
    local w, h = dimensions(child, editors, source, axis)
    if node[1] == 'row' then
      columns, rows = columns + w, math.max(rows, h)
    else
      columns, rows = math.max(columns, w), rows + h
    end
  end
  return columns, rows
end

---在另一侧显示当前文件，保持原窗口焦点；已显示同一 buffer 时保留目标的独立视图
---@param opts EditorSplitOptions
function M.show(opts)
  local max_rows = opts.max_rows == nil and 2 or opts.max_rows
  local max_columns = opts.max_columns == nil and 2 or opts.max_columns
  for name, value in pairs({ max_rows = max_rows, max_columns = max_columns }) do
    assert(type(value) == 'number' and value >= 1 and value < math.huge and value % 1 == 0,
      name .. ' must be a positive integer')
  end

  local source = vim.api.nvim_get_current_win()
  if vim.t.vv_bufferline_ignore or not is_editor(source) then return end

  local wins, editors = {}, {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_editor(win) then
      wins[#wins + 1] = win
      editors[win] = true
    end
  end

  -- 优先复用右侧／下方；到达边缘且还有额度时继续扩展，达到上限后回看左侧／上方
  -- 只取任意一侧会让第三行／列永远无法创建，即使配置已放宽上限
  local targets = opposite(source, wins, opts.axis)
  local target = targets.forward
  if not target then
    local columns, rows = dimensions(vim.fn.winlayout(), editors, source, opts.axis)
    if #wins >= max_rows * max_columns or columns > max_columns or rows > max_rows then
      target = targets.backward
      if not target then return end
    end
  end

  local buf = vim.api.nvim_win_get_buf(source)
  if target and vim.api.nvim_win_get_buf(target) == buf then return end

  -- 在修改窗口之前加载依赖；失败时不留下已创建但未纳入标签栏的分屏
  local bufferline = require('vv-bufferline')
  local ok, err = pcall(function()
    if not target then
      vim.api.nvim_win_call(source, function()
        vim.cmd(opts.axis == 'vertical' and 'belowright vsplit' or 'belowright split')
        target = vim.api.nvim_get_current_win()
      end)
    else
      vim.api.nvim_win_set_buf(target, buf)
    end
    -- 显式查看是固定标签，不是 explorer 的临时预览；保留目标组中原有标签
    bufferline.clear_preview(target, nil, { promote = true })
  end)
  if not ok then vim.notify('另一侧查看失败：' .. tostring(err), vim.log.levels.ERROR) end
end

---@class EditorSplitOptions
---@field axis 'horizontal'|'vertical' horizontal 对应上下，vertical 对应左右
---@field max_rows? integer 最大文件窗口行数，正整数；默认 2
---@field max_columns? integer 最大文件窗口列数，正整数；默认 2

return M
