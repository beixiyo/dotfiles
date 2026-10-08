-- fff grep 列表裁缩进 × 真实 picker 端到端（fixture 目录 + 独立 db）
-- 验证的契约（grep_renderer.lua）：
--   1. 列表匹配行不显示源码前导缩进（空格与 tab）
--   2. 匹配高亮（grep_match extmark）仍精确覆盖匹配词：match_ranges 随裁剪同步左移
--   3. 确认选择后光标落在源码原始列：col 不随显示裁剪改变（fff 自带 trim_whitespace 会把 col 一并左移）
local H = dofile('tests/helpers.lua')
local T, child = H.new_set({ 'VV_TEST_FFF' })

T['裁掉缩进但保留原始列与匹配高亮'] = function()
  child.lua_func(function()
    vim.o.columns = 200
    vim.o.lines = 50

    local base = vim.fn.tempname()
    local root = base .. '/repo'
    vim.fn.mkdir(root, 'p')
    vim.fn.writefile({ 'local top = 1', '    local needle = 1', '\t\tneedle()' }, root .. '/a.lua')
    vim.fn.system({ 'git', '-C', root, 'init', '-q' })

    vim.cmd.cd(root)
    require('fff').setup({
      base_path = root,
      lazy_sync = true,
      frecency = { db_path = base .. '/frecency' },
      history = { db_path = base .. '/history' },
      logging = { enabled = false },
    })
    require('fff.core').ensure_initialized()
    require('fff.file_picker').setup()
    check(require('fff.file_picker').wait_for_initial_scan(15000), 'fff 初始索引超时')

    vim.cmd.edit(root .. '/a.lua')
    require('fff').live_grep({ query = 'needle', renderer = require('plugins.specs.tools.fff.grep_renderer') })

    local S = require('fff.picker_ui.picker_ui_state').state
    wait(function() return S.active and #(S.items or {}) == 2 end, 5000, 'picker 未返回 2 条匹配')

    -- items 先于列表绘制就绪，等两条匹配行都画进 list buffer
    local lines
    wait(function()
      lines = vim.api.nvim_buf_get_lines(S.list_buf, 0, -1, false)
      local text = table.concat(lines, '\n')
      return text:find(':2:%d+') ~= nil and text:find(':3:%d+') ~= nil
    end, 5000, '列表未渲染出两条匹配行')
    local function find_line(pattern)
      for i, line in ipairs(lines) do
        if line:find(pattern) then return i - 1, line end
      end
    end

    -- 1. 缩进被裁掉：location 与正文之间只剩 renderer 固定的两个空格分隔
    local row_space, line_space = find_line(':2:%d+')
    local row_tab, line_tab = find_line(':3:%d+')
    check(line_space and line_space:match(':2:%d+  local needle'), '空格缩进未裁掉: ' .. tostring(line_space))
    check(line_tab and line_tab:match(':3:%d+  needle%(%)'), 'tab 缩进未裁掉: ' .. tostring(line_tab))
    check(line_space:match(':2:11 '), '显示的列号必须是源码原始列（11），不能随裁剪变化')

    -- 2. 匹配高亮覆盖 needle 本身
    local match_hl = S.config.hl.grep_match or 'IncSearch'
    local function highlighted_text(row, line)
      local ns = vim.api.nvim_get_namespaces()
      for _, id in pairs(ns) do
        for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(S.list_buf, id, { row, 0 }, { row, -1 }, { details = true })) do
          if mark[4].hl_group == match_hl then return line:sub(mark[3] + 1, mark[4].end_col) end
        end
      end
    end
    eq(highlighted_text(row_space, line_space), 'needle', '空格缩进行的匹配高亮必须覆盖 needle')
    eq(highlighted_text(row_tab, line_tab), 'needle', 'tab 缩进行的匹配高亮必须覆盖 needle')

    -- 3. 选中第一条匹配（第 2 行）确认后光标落在原始列
    local target
    for i, item in ipairs(S.items) do
      if item.line_number == 2 then target = i end
    end
    S.cursor = target
    require('fff.picker_ui.picker_ui').select()
    wait(function() return not S.active end, 3000, '确认后 picker 未关闭')
    wait(function() return vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 2, 10 }) end,
      3000, '确认后光标必须落在源码原始位置（第 2 行 needle 起始列）')

    pcall(require('fff.fuzzy').cleanup_file_picker)
    vim.fn.delete(base, 'rf')
  end)
end

return T
