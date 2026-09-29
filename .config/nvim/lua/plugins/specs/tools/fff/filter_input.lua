-- fff 输入框 <M-p> 筛选弹窗：与 query 中的筛选 token 双向同步
--   打开：弹窗默认值 = 当前 query 里的全部筛选 token；若这些 token 由上次弹窗编译而来，回显当时的原始输入
--   确认：输入按 telescope 时代的 glob 语义编译（见 query.compile_filters），整体替换这些 token，
--         搜索词保持原序不动；清空输入 = 移除全部筛选；取消 = 不改；编译失败时提示并保持 query 不变
-- fff 输入框 buffer 行是唯一事实源：只改 buffer，由 fff 的 on_lines → on_input_change 链路刷新结果
-- 依赖 fff 内部模块 picker_ui_state（上游重构时可能失效，升级 fff 后需回归）
local Query = require('plugins.specs.tools.fff.query')
local PathCompletion = require('vv-utils.path_completion')

local M = {}

local completion_seq = 0
-- 编译后的筛选 token（空格拼接）→ 用户原始输入，供再次打开时回显简写而非 brace
local source_by_filters = {}

---@param state table fff picker_ui_state.state
---@return string
local function read_query(state)
  local line = vim.api.nvim_buf_get_lines(state.input_buf, 0, 1, false)[1] or ''
  local prompt = state.config.prompt
  return vim.startswith(line, prompt) and line:sub(#prompt + 1) or line
end

---@param state table
---@param query string
local function write_query(state, query)
  local line = state.config.prompt .. query
  vim.api.nvim_set_option_value('modifiable', true, { buf = state.input_buf })
  vim.api.nvim_buf_set_lines(state.input_buf, 0, -1, false, { line })
  if vim.api.nvim_win_is_valid(state.input_win) then
    vim.api.nvim_win_set_cursor(state.input_win, { 1, #line })
  end
end

--- 注册一次性的 customlist 补全函数，返回函数名；调用方负责在弹窗结束后置空
---@return string
local function register_completion()
  completion_seq = completion_seq + 1
  local name = '__fff_filter_complete_' .. completion_seq
  _G[name] = function(arglead, cmdline, cursor_pos)
    local input = cmdline or arglead or ''
    local cursor = math.max(0, math.min(cursor_pos or #input, #input))
    local result = PathCompletion.glob(input, { cwd = require('fff.conf').get().base_path, cursor = cursor })
    local before = input:sub(1, result.start_col)
    local after = input:sub(cursor + 1)
    return vim.tbl_map(function(item) return before .. item.word .. after end, result.items)
  end
  return name
end

--- 打开筛选弹窗；仅在 fff picker 激活时有效
function M.open()
  local state = require('fff.picker_ui.picker_ui_state').state
  if not state.active or not state.input_buf then return end

  local mode = state.mode == 'grep' and 'grep' or 'files'
  local input_buf = state.input_buf
  local completion = register_completion()
  local current = table.concat(Query.split(read_query(state), mode).filters, ' ')

  vim.ui.input({
    prompt = 'Filter: ',
    default = source_by_filters[current] or current,
    completion = 'customlist,v:lua.' .. completion,
  }, function(input)
    _G[completion] = nil
    -- 弹窗期间 picker 可能已关闭或被重开，旧回调不得写回新 picker
    if input == nil or not state.active or state.input_buf ~= input_buf then return end
    input = vim.trim(input)
    local query, err = Query.replace_filters(read_query(state), input, mode)
    if not query then
      vim.notify('fff filter: ' .. err, vim.log.levels.ERROR)
      return
    end
    source_by_filters[table.concat(Query.split(query, mode).filters, ' ')] = input
    write_query(state, query)
  end)
end

return M
