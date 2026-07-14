-- 文档注释智能编辑（/** */ 块）
-- 1. /** 自动闭合：输入 /* 后再按 * → /**  */，光标留在中间
-- 2. Enter 展开：/** | */ 内按回车 → 三行展开，光标停在 * 行
-- 3. * 续写由 formatoptions r/o 处理（autocmd.lua 中已开启）

local filetypes = {
  "javascript", "typescript", "javascriptreact", "typescriptreact",
  "vue", "java", "c", "cpp", "css", "scss", "less", "rust", "go", "php",
}

local function augroup(name)
  return vim.api.nvim_create_augroup("my_nvim_" .. name, { clear = true })
end

vim.api.nvim_create_autocmd("FileType", {
  group = augroup("doc_comment_close"),
  pattern = filetypes,
  callback = function(ev)
    vim.keymap.set("i", "*", function()
      local row, col = unpack(vim.api.nvim_win_get_cursor(0))
      local line = vim.api.nvim_get_current_line()
      local before = line:sub(1, col)
      local after = line:sub(col + 1)

      if before:match("/%*$") and not after:match("^%s*%*/") then
        vim.api.nvim_set_current_line(before .. "*  */" .. after)
        vim.api.nvim_win_set_cursor(0, { row, col + 2 })
        return
      end

      vim.api.nvim_feedkeys("*", "n", false)
    end, { buffer = ev.buf })
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  group = augroup("doc_comment_enter"),
  pattern = filetypes,
  callback = function(ev)
    vim.keymap.set("i", "<CR>", function()
      local row, col = unpack(vim.api.nvim_win_get_cursor(0))
      local line = vim.api.nvim_get_current_line()
      local before = line:sub(1, col)
      local after = line:sub(col + 1)

      if before:match("/%*%*%s*$") and after:match("^%s*%*/") then
        local indent = line:match("^(%s*)")
        vim.api.nvim_buf_set_lines(0, row - 1, row, false, {
          before:gsub("%s+$", ""),
          indent .. " * ",
          indent .. " " .. after:gsub("^%s+", ""),
        })
        vim.api.nvim_win_set_cursor(0, { row + 1, #indent + 3 })
        return
      end

      -- 让 mini.pairs 处理：在 {} [] () 之间按 Enter 时自动缩进展开
      vim.api.nvim_feedkeys(require('mini.pairs').cr(), 'n', false)
    end, { buffer = ev.buf })
  end,
})
