-- 编辑器通用行为

local function augroup(name)
  return vim.api.nvim_create_augroup("my_nvim_" .. name, { clear = true })
end

-- 文件外部修改检测
-- BufEnter：切回文件窗口那一刻必触发
-- FocusGained：从别的窗口/另一个 nvim 切回来（OS 级焦点变化）
-- TermClose/TermLeave：退出内嵌终端
vim.api.nvim_create_autocmd({ "BufEnter", "FocusGained", "TermClose", "TermLeave" }, {
  group = augroup("checktime"),
  callback = function()
    if vim.o.buftype ~= "nofile" then
      vim.cmd("checktime")
    end
  end,
})

-- 复制高亮
vim.api.nvim_create_autocmd("TextYankPost", {
  group = augroup("highlight_yank"),
  callback = function()
    local hl = vim.hl or vim.highlight
    ;(hl.hl_op or hl.on_yank)()
  end,
})

-- 窗口尺寸变化时重新平衡分割
vim.api.nvim_create_autocmd({ "VimResized" }, {
  group = augroup("resize_splits"),
  callback = function()
    local current_tab = vim.fn.tabpagenr()
    vim.cmd("tabdo wincmd =")
    vim.cmd("tabnext " .. current_tab)
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
