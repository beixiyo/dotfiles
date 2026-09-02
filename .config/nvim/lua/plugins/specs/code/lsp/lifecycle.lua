-- LSP client 退出生命周期兜底
--
-- Neovim 自带的 VimLeavePre 处理器只对「已初始化」的 client 发 shutdown，
-- 还卡在 initialize 阶段的 client 会被直接遗弃；oxlint 这类 server 收到 stdin EOF
-- 并不会自行退出，于是每次「LSP 尚未就绪就退出 nvim」都留下一个孤儿进程
-- （典型场景：hook 起 headless nvim 处理完文件 2 秒内 qa!，而 oxlint 初始化要 2 秒）
--
-- 两层兜底：
--   1. exit_timeout：已初始化的 client 退出时真正等到 shutdown 完成，超时再强杀
--      （默认 false 表示发完 shutdown 立即退出，server 应答慢一点就会漏）
--   2. VimLeavePre：未初始化的 client 直接强制 stop（等价于 SIGTERM）

local M = {}

--- 退出时等待 server 完成 shutdown 的上限；正常情况几毫秒就返回
local EXIT_TIMEOUT_MS = 500

function M.setup()
  vim.lsp.config('*', { exit_timeout = EXIT_TIMEOUT_MS })

  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = vim.api.nvim_create_augroup('LspStopUninitialized', { clear = true }),
    desc = 'LSP: force-stop clients that never finished initializing',
    callback = function()
      -- _uninitialized 是 get_clients 的内部过滤开关，默认会把未初始化的 client 藏掉
      for _, client in ipairs(vim.lsp.get_clients({ _uninitialized = true })) do
        if not client.initialized then client:stop(true) end
      end
    end,
  })
end

return M
