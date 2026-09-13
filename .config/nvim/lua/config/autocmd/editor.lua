-- 编辑器通用行为

local function augroup(name)
  return vim.api.nvim_create_augroup("my_nvim_" .. name, { clear = true })
end

-- 文件外部修改检测
-- Nvim 0.13+ 的 'autoread' 自带文件系统 watcher，可在外部进程写入后即时检查
-- 旧版没有 watcher，仍在切回 buffer/窗口或离开内嵌终端时用 :checktime 兜底
if vim.fn.has('nvim-0.13') == 0 then
  vim.api.nvim_create_autocmd({ 'BufEnter', 'FocusGained', 'TermClose', 'TermLeave' }, {
    group = augroup('checktime'),
    callback = function()
      if vim.o.buftype ~= 'nofile' then
        vim.cmd('checktime')
      end
    end,
  })
end

-- 复制高亮
vim.api.nvim_create_autocmd('TextYankPost', {
  group = augroup('highlight_yank'),
  callback = function()
    if vim.hl.hl_op then
      vim.hl.hl_op()
    else
      -- 0.13 起弃用了
      ---@diagnostic disable-next-line: deprecated
      vim.hl.on_yank()
    end
  end,
})

-- 窗口尺寸变化时重新平衡分割
vim.api.nvim_create_autocmd({ 'VimResized' }, {
  group = augroup('resize_splits'),
  callback = function()
    local current_win = vim.api.nvim_get_current_win()

    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
      local ok, managed = pcall(vim.api.nvim_tabpage_get_var, tab, 'vv_bufferline_ignore')

      if not ok or not managed then
        local win = vim.iter(vim.api.nvim_tabpage_list_wins(tab)):find(function(candidate)
          return vim.api.nvim_win_get_config(candidate).relative == ''
        end)

        if win then
          vim.api.nvim_win_call(win, function() vim.cmd('wincmd =') end)
        end
      end
    end

    if vim.api.nvim_win_is_valid(current_win) then
      vim.api.nvim_set_current_win(current_win)
    end
  end,
})

-- 恢复上次光标位置
vim.api.nvim_create_autocmd("BufReadPost", {
  group = augroup("last_loc"),
  callback = function(event)
    local exclude = { "gitcommit" }
    local buf = event.buf
    if vim.tbl_contains(exclude, vim.bo[buf].filetype) or vim.b[buf].my_nvim_last_loc then
      return
    end
    vim.b[buf].my_nvim_last_loc = true
    local mark = vim.api.nvim_buf_get_mark(buf, '"')
    local lcount = vim.api.nvim_buf_line_count(buf)
    if mark[1] > 0 and mark[1] <= lcount then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
})

-- 进入插入模式时清除搜索高亮
vim.api.nvim_create_autocmd({ "InsertEnter" }, {
  group = augroup("clear_search"),
  callback = function()
    vim.schedule(function()
      vim.cmd("nohlsearch")
    end)
  end,
})
