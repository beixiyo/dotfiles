-- 保存相关

local function augroup(name)
  return vim.api.nvim_create_augroup("my_nvim_" .. name, { clear = true })
end

-- 保存前自动创建缺失目录
vim.api.nvim_create_autocmd({ "BufWritePre" }, {
  group = augroup("auto_create_dir"),
  callback = function(event)
    if event.match:match("^%w%w+:[\\/][\\/]") then
      return
    end
    local file = vim.uv.fs_realpath(event.match) or event.match
    vim.fn.mkdir(vim.fn.fnamemodify(file, ":p:h"), "p")
  end,
})

-- 保存前删除行尾空白
vim.api.nvim_create_autocmd("BufWritePre", {
  group = augroup("trim_trailing"),
  pattern = "*",
  callback = function(event)
    if vim.bo[event.buf].filetype == ""
      or vim.bo[event.buf].filetype == "markdown"
      or vim.bo[event.buf].buftype ~= ""
    then
      return
    end
    local view = vim.fn.winsaveview()
    vim.cmd([[keeppatterns %s/\s\+$//e]])
    vim.fn.winrestview(view)
  end,
})
