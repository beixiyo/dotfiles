-- 修复 inotify watch 配额耗尽
--
-- ~ 本身是 dotfiles 仓库,在 ~ 下开文件时 LSP 工作区根会落到 $HOME
-- Neovim 的 LSP 文件监听(:h inotify-limitations)会对工作区根跑
-- `inotifywait --recursive`,于是递归监听 ~/.npm ~/.cache ~/.cargo 等
-- 十几万个目录,瞬间吃满 inotify watch 配额 → "inotify(7) limit reached"
-- 这里只掐掉「工作区根 == 家目录」这一病态情况,真实项目(~/code/*)有自己的
-- 根,文件监听照常工作

local M = {}

function M.setup()
  local wf = require('vim.lsp._watchfiles')
  local orig_watchfunc = wf._watchfunc
  local home = vim.fs.normalize(vim.uv.os_homedir())

  wf._watchfunc = function(base_dir, opts, callback)
    if vim.fs.normalize(base_dir) == home then
      return function() end
    end
    return orig_watchfunc(base_dir, opts, callback)
  end
end

return M
