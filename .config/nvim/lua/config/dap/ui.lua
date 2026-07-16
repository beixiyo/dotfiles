-- DAP 通用窗口、面板与符号配置
local M = {}

local function setup_session_focus(dap)
  -- Main 与 Renderer 可同时运行；哪个 session 命中断点，调试面板就跟随哪个
  dap.listeners.after.event_stopped['focus_stopped_session'] = function(session)
    vim.schedule(function()
      if not session.closed and dap.session() ~= session then dap.set_session(session) end
    end)
  end

  -- 新建 child/Renderer session 时 nvim-dap 会切换当前 session，不能覆盖正在检查的断点
  dap.listeners.on_session['preserve_stopped_session'] = function(previous, current)
    if not previous or not previous.stopped_thread_id then return end
    if current and current.stopped_thread_id then return end

    vim.schedule(function()
      if not previous.closed and previous.stopped_thread_id and dap.session() == current then
        dap.set_session(previous)
      end
    end)
  end
end

local function setup_switchbuf(dap)
  -- dap-view 的固定窗口启用了 winfixbuf，不能直接替换成源码 buffer
  -- 优先复用当前标签页里的源码窗口，否则寻找普通窗口，最后才新建窗口
  dap.defaults.fallback.switchbuf = function(buf, line, column)
    local current = vim.api.nvim_get_current_win()
    local target

    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.api.nvim_win_get_buf(win) == buf and not vim.wo[win].winfixbuf then
        target = win
        break
      end
    end

    if not target and not vim.wo[current].winfixbuf and vim.bo[vim.api.nvim_win_get_buf(current)].buftype == '' then
      target = current
    end

    if not target then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local win_buf = vim.api.nvim_win_get_buf(win)
        if not vim.wo[win].winfixbuf and vim.bo[win_buf].buftype == '' then
          target = win
          break
        end
      end
    end

    if not target then
      vim.cmd('aboveleft new')
      target = vim.api.nvim_get_current_win()
    end

    vim.api.nvim_set_current_win(target)
    vim.api.nvim_win_set_buf(target, buf)

    local target_line = math.min(math.max(line, 1), vim.api.nvim_buf_line_count(buf))
    local text = vim.api.nvim_buf_get_lines(buf, target_line - 1, target_line, false)[1] or ''
    local target_column = math.min(math.max(column - 1, 0), #text)
    vim.api.nvim_win_set_cursor(target, { target_line, target_column })
  end
end

---@param dap table
function M.setup(dap)
  setup_switchbuf(dap)
  setup_session_focus(dap)

  local icons = require('vv-icons')

  -- 默认展示最常用的 Scopes，并隐藏通常为空的独立 dap-terminal
  require('dap-view').setup({
    auto_toggle = true,
    icons = {
      disconnect = icons.debug_disconnect,
      pause = icons.debug_pause,
      play = icons.debug_continue,
      run_last = icons.debug_run_last,
      step_into = icons.debug_step_into,
      step_out = icons.debug_step_out,
      step_over = icons.debug_step_over,
      terminate = icons.debug_terminate,
    },
    winbar = {
      default_section = 'scopes',
      controls = { enabled = true },
    },
    virtual_text = {
      enabled = true,
      position = 'eol',
    },
    windows = {
      position = 'below',
      size = 0.3,
      terminal = {
        hide = true,
      },
    },
    render = {
      breakpoints = {
        format = function(line, lnum, path)
          return {
            { text = require('vv-utils').path.collapse_middle(path), hl = 'FileName' },
            { text = lnum, hl = 'LineNumber' },
            { text = line, hl = true },
          }
        end,
      },
    },
  })

  require('config.dap.panel').setup()
  require('config.dap.signs').setup()
end

return M
