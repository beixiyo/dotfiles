-- 管理 leaf 预览的来源与关闭动作，供外部编辑器通过 RPC 返回源码
local M = {}
local sessions = {}

---登记一个预览；关闭动作由创建窗口的调用方提供
---@param id string
---@param context { buf: integer, win: integer, close: fun(pid: integer) }
function M.register(id, context)
  sessions[id] = context
end

---移除已退出的预览，避免旧编辑器回调再次操作窗口
---@param id string
function M.remove(id)
  sessions[id] = nil
end

---定位预览对应的原 buffer，并在 RPC 响应后关闭预览
---@param id string
---@param line integer
---@param pid integer 发起编辑器调用的 leaf 进程，避免关闭后来创建的预览
function M.return_to_source(id, line, pid)
  local context = sessions[id]
  if not context or context.returning then return end
  context.returning = true

  local valid = vim.api.nvim_buf_is_valid(context.buf) and vim.api.nvim_buf_is_loaded(context.buf)
    and vim.api.nvim_win_is_valid(context.win)
  local positioned, position_error = false, nil

  if valid then
    positioned, position_error = pcall(function()
      local target = math.max(1, math.min(line, vim.api.nvim_buf_line_count(context.buf)))
      vim.api.nvim_win_set_buf(context.win, context.buf)
      vim.api.nvim_win_set_cursor(context.win, { target, 0 })
    end)
  end

  -- 关闭预览可能终止发起 RPC 的 helper，先让请求返回
  vim.schedule(function()
    -- q/窗口关闭已经移除旧 session 时，不再结束旧 PID
    if sessions[id] ~= context then return end
    sessions[id] = nil
    context.close(pid)

    if positioned and vim.api.nvim_win_is_valid(context.win) and vim.api.nvim_buf_is_valid(context.buf) then
      vim.cmd.stopinsert()
      vim.api.nvim_set_current_win(context.win)
      vim.api.nvim_win_call(context.win, function() vim.cmd('normal! zz') end)
    elseif position_error then
      vim.notify('Cannot return to Markdown source: ' .. tostring(position_error), vim.log.levels.ERROR)
    elseif not valid then
      vim.notify('Markdown source buffer or window has been closed', vim.log.levels.WARN)
    end
  end)
end

return M
