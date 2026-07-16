-- 扩展 dap-view 面板交互：断点实时预览与快捷关闭
local M = {}

local api = vim.api
local previews = {}

---@class DapPanelPreview
---@field win integer
---@field buf integer
---@field view vim.fn.winsaveview.ret

---恢复实时预览前的源码 buffer 与视图
---@param panel_buf integer
local function restore_preview(panel_buf)
  local preview = previews[panel_buf]
  previews[panel_buf] = nil

  if not preview then return end
  if not api.nvim_win_is_valid(preview.win) then return end
  if not api.nvim_buf_is_valid(preview.buf) then return end

  api.nvim_win_set_buf(preview.win, preview.buf)
  api.nvim_win_call(preview.win, function() vim.fn.winrestview(preview.view) end)
end

---确认当前断点，保留预览位置并执行 dap-view 的正式跳转
---@param panel_buf integer
local function commit_breakpoint(panel_buf)
  local state = require('dap-view.state')
  if state.current_section ~= 'breakpoints' then return end

  local panel_win = state.winnr
  if not panel_win or not api.nvim_win_is_valid(panel_win) then return end

  local row = api.nvim_win_get_cursor(panel_win)[1]
  if not state.breakpoint_paths_by_line[row] then return end

  previews[panel_buf] = nil
  require('dap-view.breakpoints.actions').jump(row)
end

---寻找当前标签页中适合展示源码的窗口
---@param target_buf integer
---@param panel_win integer
---@return integer?
local function find_source_win(target_buf, panel_win)
  local fallback

  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if win ~= panel_win and not vim.wo[win].winfixbuf then
      local buf = api.nvim_win_get_buf(win)

      if buf == target_buf then return win end

      if not fallback and vim.bo[buf].buftype == '' then fallback = win end
    end
  end

  return fallback
end

---在源码窗口预览当前断点，同时保留 dap-view 面板焦点
function M.preview_breakpoint()
  local state = require('dap-view.state')
  local panel_win = state.winnr
  local panel_buf = state.bufnr

  if state.current_section ~= 'breakpoints' then return end
  if not panel_win or not api.nvim_win_is_valid(panel_win) then return end
  if not panel_buf or not api.nvim_buf_is_valid(panel_buf) then return end
  if api.nvim_get_current_win() ~= panel_win then return end

  local row = api.nvim_win_get_cursor(panel_win)[1]
  local path = state.breakpoint_paths_by_line[row]
  local line = state.breakpoint_lines_by_line[row]

  if not path or not line then return end

  local target_buf = require('dap-view.views.util').get_bufnr_from_path(path)
  if not target_buf then return end

  vim.fn.bufload(target_buf)

  local preview = previews[panel_buf]
  local source_win = preview and api.nvim_win_is_valid(preview.win) and preview.win
    or find_source_win(target_buf, panel_win)
  if not source_win then return end

  if not preview then
    previews[panel_buf] = {
      win = source_win,
      buf = api.nvim_win_get_buf(source_win),
      view = api.nvim_win_call(source_win, vim.fn.winsaveview),
    }
  end

  api.nvim_win_set_buf(source_win, target_buf)

  local target_line = math.min(math.max(line, 1), api.nvim_buf_line_count(target_buf))
  api.nvim_win_set_cursor(source_win, { target_line, 0 })

  -- dap-view 会在切换 section 时重装自己的按键，因此在断点预览时覆盖 Enter
  -- Enter 表示确认本次预览，其他离开面板的方式都由 WinLeave 回滚
  vim.keymap.set('n', '<CR>', function() commit_breakpoint(panel_buf) end, {
    buffer = panel_buf,
    desc = 'Jump to breakpoint',
    nowait = true,
    silent = true,
  })
end

---为每次新建的 dap-view 主面板安装局部交互
---@param buf integer
local function attach(buf)
  vim.keymap.set('n', 'q', function()
    restore_preview(buf)
    require('dap-view').close(true)
  end, {
    buffer = buf,
    desc = 'Close debug panel',
    nowait = true,
    silent = true,
  })

  api.nvim_create_autocmd('CursorMoved', {
    buffer = buf,
    callback = M.preview_breakpoint,
    desc = 'Preview the selected DAP breakpoint',
  })

  api.nvim_create_autocmd('WinLeave', {
    buffer = buf,
    callback = function() restore_preview(buf) end,
    desc = 'Restore source position after leaving the DAP panel',
  })

  api.nvim_create_autocmd('BufWipeout', {
    buffer = buf,
    callback = function() restore_preview(buf) end,
    desc = 'Restore source position after closing the DAP panel',
  })
end

function M.setup()
  local group = api.nvim_create_augroup('DapViewPanel', { clear = true })

  api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'dap-view',
    callback = function(args) attach(args.buf) end,
    desc = 'Extend dap-view panel interactions',
  })
end

return M
