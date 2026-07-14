-- 将当前配置根目录插入到 runtimepath 最前端
-- 如果不添加此行，Neovim 将无法在当前配置目录下识别并加载 lua/ 目录中的模块，导致 require("config...") 等调用失败
vim.opt.rtp:prepend(vim.fn.stdpath("config"))

-- 若启动参数为目录：cd 过去并把该 arg/buffer 清掉，使启动效果等价于先 `cd <dir>` 再 `nvim`
-- （dashboard.auto_open_check 判定 argc()==0 + 无带名 buffer → 自动开启动页）
do
  local arg = vim.fn.argv(0)
  if arg and arg ~= "" and vim.fn.isdirectory(arg) == 1 then
    local abs = vim.fn.fnamemodify(arg, ":p")
    vim.cmd.cd(abs)
    pcall(vim.cmd, "argdelete " .. vim.fn.fnameescape(arg))
    local abs_noslash = abs:gsub("/$", "")
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(b)
      if name ~= "" and (name == abs or name == abs_noslash) then
        pcall(vim.api.nvim_buf_delete, b, { force = true })
      end
    end
    -- buf_delete 后 nvim 自动补了一个空 buffer，不让它出现在 bufferline
    local cur = vim.api.nvim_get_current_buf()
    if vim.api.nvim_buf_get_name(cur) == "" then
      vim.bo[cur].buflisted = false
    end
  end
end

-- 模块化加载核心配置
-- pack 必须在 keymaps 之前：keymaps.lua 顶部 `require('vv-icons')` / `require('vv-utils')`，
-- 由 pack 通过 spec 的 priority + dependencies 加载好它们
require("config.options")
require("config.neovide")
require("config.clipboard")
require("pack")
require("config.keymaps")
require("config.autocmd")
require("config.cmd")
