-- Tailwind CSS language server
--
-- 不由 Mason 安装，版本由 ~/.config/mise/config.toml 管理

local M = {}

function M.setup()
  local default = vim.lsp.config.tailwindcss
  local default_root_dir = default and default.root_dir

  -- 官方 server 只有 Node 实现；限制堆内存，避免上游扫描问题拖垮整机
  vim.lsp.config['tailwindcss'] = {
    cmd = { 'tailwindcss-language-server', '--stdio' },
    cmd_env = { NODE_OPTIONS = '--max-old-space-size=1024' },
    filetypes = {
      'astro',
      'css',
      'html',
      'javascript',
      'javascriptreact',
      'less',
      'postcss',
      'sass',
      'scss',
      'svelte',
      'typescript',
      'typescriptreact',
      'vue',
    },
    root_dir = function(bufnr, on_dir)
      if type(default_root_dir) ~= 'function' then return end
      default_root_dir(bufnr, function(root)
        if type(root) ~= 'string' or root == '' then return end

        local home = vim.uv.os_homedir()
        if type(home) == 'string' and vim.fs.normalize(root) == vim.fs.normalize(home) then return end

        on_dir(root)
      end)
    end,
    -- 显式指定入口可跳过全仓扫描探测，项目可在 .nvim.lua 覆盖：
    -- settings = { tailwindCSS = { experimental = { configFile = 'src/app.css' } } }
  }
end

return M
