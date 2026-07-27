-- Tailwind CSS language server
--
-- 不由 Mason 安装，版本由 ~/.config/mise/config.toml 管理

local M = {}

function M.setup()
  -- 官方 server 只有 Node 实现；限制堆内存，避免上游扫描问题拖垮整机
  vim.lsp.config['tailwindcss'] = {
    cmd = { 'tailwindcss-language-server', '--stdio' },
    cmd_env = { NODE_OPTIONS = '--max-old-space-size=1024' },
    -- 显式指定入口可跳过全仓扫描探测，项目可在 .nvim.lua 覆盖：
    -- settings = { tailwindCSS = { experimental = { configFile = 'src/app.css' } } }
  }
end

return M
