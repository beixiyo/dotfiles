local M = {}

function M.setup()
  -- Tailwind 的 @tailwind / @apply / @theme 等不在 CSS 规范里，默认会被报成未知 at-rule
  local lang = { validate = true, lint = { unknownAtRules = 'ignore' } }

  vim.lsp.config('cssls', {
    init_options = { provideFormatter = false },
    settings = { css = lang, scss = lang, less = lang },
  })
end

return M
