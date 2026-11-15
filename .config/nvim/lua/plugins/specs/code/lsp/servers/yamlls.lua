local M = {}

function M.setup()
  vim.lsp.config('yamlls', {
    settings = {
      redhat = { telemetry = { enabled = false } },
      yaml = {
        format = { enable = false },
        -- 默认要求 key 按字母序，对配置文件没有意义
        keyOrdering = false,
      },
    },
  })
end

return M
