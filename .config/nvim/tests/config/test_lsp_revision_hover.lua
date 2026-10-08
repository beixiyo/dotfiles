-- revision hover 必须把 diff 光标位置映射到真实文件 URI，而不是向匿名 scratch 请求 LSP
-- mock 只打外部 I/O 边界（vim.lsp.buf_request），业务逻辑全真实
-- 注：hover.lua 用 params builder 回调签名（buf_request 第三参是 function），
-- mock 里 params({ offset_encoding = ... }) 是调用该 builder 取参数表，不是 bug
local H = dofile('tests/helpers.lua')
local T, child = H.new_set()

T['revision hover 指向 worktree 真实文档'] = function()
  child.lua_func(function()
    local source_path = vim.fn.tempname() .. '.lua'
    local source_line = 'local 名称 = true'
    vim.fn.writefile({ source_line }, source_path)
    local resolved_source_path = assert(vim.uv.fs_realpath(source_path))

    local scratch = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(scratch, 0, -1, false, { source_line })
    vim.api.nvim_win_set_buf(0, scratch)
    local byte_col = #'local 名'
    vim.api.nvim_win_set_cursor(0, { 1, byte_col })

    local request
    local original_buf_request = vim.lsp.buf_request
    vim.lsp.buf_request = function(bufnr, method, params, handler)
      request = {
        bufnr = bufnr,
        method = method,
        params = params({ offset_encoding = 'utf-16' }),
        handler = handler,
      }
      return {}, function() end
    end

    require('plugins.specs.code.lsp.hover').toggle_revision({
      winid = vim.api.nvim_get_current_win(),
      source_path = source_path,
    })
    vim.lsp.buf_request = original_buf_request

    check(request ~= nil, 'revision K 应发出 LSP hover 请求')
    check(request.method == 'textDocument/hover', 'revision K 应请求 textDocument/hover')
    check(vim.api.nvim_buf_get_name(request.bufnr) == resolved_source_path, 'LSP client 应取自真实 worktree buffer')
    check(request.params.textDocument.uri == vim.uri_from_fname(resolved_source_path), '请求 URI 应指向真实文件')
    check(request.params.position.line == 0, '请求行号应来自 revision diff 光标')
    check(request.params.position.character == vim.str_utfindex(source_line, 'utf-16', byte_col, false), '请求列应按 LSP client 的 position encoding 转换')
    check(type(request.handler) == 'function', 'hover 结果应交给可见文档 handler')
  end)
end

return T
