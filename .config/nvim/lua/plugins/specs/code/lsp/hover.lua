-- LSP hover 的显示与关闭策略，并为 revision scratch 提供 worktree 请求代理

local api = vim.api

local M = {}

---@return boolean closed
local function close_hover()
  local ok_docs, docs = pcall(require, 'noice.lsp.docs')
  if ok_docs and docs._messages then
    local msg = docs._messages.hover
    if msg and msg.win and msg:win() then
      docs.hide(msg)
      return true
    end
  end

  for _, win in ipairs(api.nvim_list_wins()) do
    local ok, marker = pcall(api.nvim_win_get_var, win, 'textDocument/hover')
    if ok and marker then
      pcall(api.nvim_win_close, win, true)
      return true
    end
  end
  return false
end

---切换当前 LSP buffer 的 hover 文档
function M.toggle()
  if close_hover() then
    return
  end
  vim.lsp.buf.hover({ silent = true })
end

---@class UserLspRevisionHoverContext
---@field winid integer revision diff 窗口
---@field source_path string 对应 worktree 文件的绝对路径

---用 revision 窗口的光标位置，请求对应 worktree buffer 的 LSP hover
---LSP 只认识当前工作区文档，因此历史版本内容只能按相同行列映射到 worktree
---@param context UserLspRevisionHoverContext
function M.toggle_revision(context)
  if close_hover() then
    return
  end
  if not context or not api.nvim_win_is_valid(context.winid) then
    return
  end
  if type(context.source_path) ~= 'string' or context.source_path == '' then
    return
  end

  local source_buf = vim.fn.bufadd(vim.fs.normalize(context.source_path))
  if source_buf <= 0 then
    return
  end
  if not api.nvim_buf_is_loaded(source_buf) then
    vim.fn.bufload(source_buf)
  end

  local cursor = api.nvim_win_get_cursor(context.winid)
  local line_count = api.nvim_buf_line_count(source_buf)
  local row = math.max(0, math.min(cursor[1] - 1, line_count - 1))
  local line = api.nvim_buf_get_lines(source_buf, row, row + 1, false)[1] or ''
  local byte_col = math.min(cursor[2], #line)

  local handler = vim.lsp.handlers.hover
  local ok_noice, noice_hover = pcall(require, 'noice.lsp.hover')
  if ok_noice and type(noice_hover.on_hover) == 'function' then
    handler = noice_hover.on_hover
  end

  vim.lsp.buf_request(source_buf, 'textDocument/hover', function(client)
    return {
      textDocument = vim.lsp.util.make_text_document_params(source_buf),
      position = {
        line = row,
        character = vim.str_utfindex(line, client.offset_encoding, byte_col, false),
      },
    }
  end, handler, function() end)
end

return M
