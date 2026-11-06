-- TypeScript LSP：默认使用 tsrs，保留官方 Go 版 tsc 供手动切换与缺失时回退
--
-- typescript@7 的正式二进制已从预览期 tsgo 改名为 tsc，但 nvim-lspconfig
-- 目前仍只提供 tsgo 配置，因此继承其 filetypes、monorepo root 与 Deno 排除逻辑
-- 两者复用根目录与偏好设置。版本由 ~/.config/mise/config.toml 管理
-- VV_NVIM_TS_LSP=tsc nvim 可临时切回官方版；同一进程只启用一个 TS server

local M = {}

--- 注册两个后端并返回本次应启用的 server 名称
---@return 'tsc'|'tsrs'
function M.setup()
  local tsgo_defaults = vim.lsp.config.tsgo
  if type(tsgo_defaults) ~= 'table' or type(tsgo_defaults.root_dir) ~= 'function' then
    vim.notify('[lsp] Failed to inherit tsgo defaults; TypeScript root_dir may be unavailable', vim.log.levels.WARN)
    tsgo_defaults = {}
  end

  -- 两个后端共用文件类型、根目录规则与编辑偏好，彼此不继承
  local shared = vim.tbl_deep_extend('force', tsgo_defaults, {
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

  -- 新装 mise 工具后，已打开的终端 PATH 可能还没有该工具的版本目录
  -- shim 使用 mise 当前选定的版本，也避免意外调用项目本地的 tsrs
  local tsrs = vim.fn.expand('~/.local/share/mise/shims/tsrs')
  vim.lsp.config['tsrs'] = vim.tbl_deep_extend('force', shared, {
    cmd = { tsrs, '--lsp', '--stdio' },
  })

  -- 只用全局 TypeScript 7 tsc；旧项目本地 tsc 不支持 --lsp
  vim.lsp.config['tsc'] = vim.tbl_deep_extend('force', shared, {
    cmd = { 'tsc', '--lsp', '--stdio' },
  })

  local backend = vim.env.VV_NVIM_TS_LSP or 'tsrs'
  if backend ~= 'tsrs' and backend ~= 'tsc' then
    vim.notify('[lsp] VV_NVIM_TS_LSP must be tsc or tsrs; using tsrs', vim.log.levels.WARN)
    backend = 'tsrs'
  end

  if backend == 'tsrs' and vim.fn.executable(tsrs) ~= 1 then
    vim.notify('[lsp] tsrs is unavailable; run mise install. Using tsc', vim.log.levels.WARN)
    return 'tsc'
  end

  return backend
end

return M
