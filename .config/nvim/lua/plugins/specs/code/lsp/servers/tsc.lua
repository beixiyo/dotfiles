-- TypeScript 7.0 原生 Go LSP
--
-- typescript@7 的正式二进制已从预览期 tsgo 改名为 tsc，但 nvim-lspconfig
-- 目前仍只提供 tsgo 配置，因此继承其 filetypes、monorepo root 与 Deno 排除逻辑
-- 仅覆盖正式版命令和偏好设置。版本由 ~/.config/mise/config.toml 管理

local M = {}

function M.setup()
  local tsgo_defaults = vim.lsp.config.tsgo
  if type(tsgo_defaults) ~= 'table' or type(tsgo_defaults.root_dir) ~= 'function' then
    vim.notify('[lsp] 未能继承 tsgo 默认配置，tsc 的 root_dir 可能不可用', vim.log.levels.WARN)
    tsgo_defaults = {}
  end

  -- 只用全局 TypeScript 7 tsc；旧项目本地 tsc 不支持 --lsp
  vim.lsp.config['tsc'] = vim.tbl_deep_extend('force', tsgo_defaults, {
    cmd = { 'tsc', '--lsp', '--stdio' },
    settings = {
      typescript = {
        preferences = {
          importModuleSpecifier = 'relative',
        },
      },
      javascript = {
        preferences = {
          importModuleSpecifier = 'relative',
        },
      },
    },
  })
end

return M
