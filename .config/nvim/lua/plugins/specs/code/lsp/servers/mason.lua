-- Mason 安装与 server 自动启用
--
-- 工作流：:Mason 手动安装 server → mason-lspconfig 检测到 → 自动 enable
--         → 打开对应 filetype 文件时自动 attach
-- TypeScript 与 Tailwind 脱离 Mason，由 mise 管理

local M = {}

function M.setup()
  -- dprint 仅提供格式化，实测 shutdown 后未及时退出；结束编辑器时直接终止，
  -- 保留其他 server 的优雅关闭与超时兜底，避免每次 :qa 固定等待 500ms
  vim.lsp.config('dprint', { exit_timeout = true })

  require('mason').setup({})
  require('mason-lspconfig').setup({
    ensure_installed = { 'dprint' },
    automatic_enable = {
      -- ts_ls 是 Node 包装的 tsserver，已被原生 Go 版 tsc 取代
      exclude = { 'ts_ls' },
    },
  })
end

return M
