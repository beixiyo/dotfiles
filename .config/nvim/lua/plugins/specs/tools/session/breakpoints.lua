-- 为 auto-session 保存与恢复 DAP 断点
local M = {}

function M.clear()
  local ok, breakpoints = pcall(require, 'dap.breakpoints')
  if ok then breakpoints.clear() end
end

function M.save()
  local ok, breakpoints = pcall(require, 'dap.breakpoints')
  if not ok then return nil end

  local saved = {}
  for bufnr, buffer_breakpoints in pairs(breakpoints.get()) do
    local path = vim.api.nvim_buf_get_name(bufnr)
    if path ~= '' then
      local items = {}
      for _, breakpoint in ipairs(buffer_breakpoints) do
        table.insert(items, {
          line = breakpoint.line,
          condition = breakpoint.condition,
          hitCondition = breakpoint.hitCondition,
          logMessage = breakpoint.logMessage,
        })
      end

      saved[vim.fs.normalize(path)] = items
    end
  end

  if vim.tbl_isempty(saved) then return nil end
  return vim.json.encode({ breakpoints = saved })
end

function M.restore(_, extra_data)
  local ok, data = pcall(vim.json.decode, extra_data)
  if not ok or type(data) ~= 'table' or type(data.breakpoints) ~= 'table' then return end

  -- 断点标记属于持久化 UI，不应依赖打开 dap-view 面板
  local signs_loaded = pcall(function() require('config.dap.signs').setup() end)
  if not signs_loaded then return end

  -- 加载 DAP 数据层；已有自定义 sign 不会被主模块的默认字符覆盖
  local dap_loaded = pcall(require, 'dap')
  if not dap_loaded then return end

  local loaded, breakpoints = pcall(require, 'dap.breakpoints')
  if not loaded then return end

  for path, items in pairs(data.breakpoints) do
    if type(path) == 'string' and type(items) == 'table' then
      local bufnr = vim.fn.bufnr(path, true)
      vim.fn.bufload(bufnr)

      for _, breakpoint in ipairs(items) do
        if type(breakpoint) == 'table' and type(breakpoint.line) == 'number' then
          breakpoints.set({
            condition = breakpoint.condition,
            hit_condition = breakpoint.hitCondition,
            log_message = breakpoint.logMessage,
          }, bufnr, breakpoint.line)
        end
      end
    end
  end
end

return M
