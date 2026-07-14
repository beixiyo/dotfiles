-- Supermaven AI 补全
---@type PackSpec
return {
  desc = 'Supermaven AI 代码补全',
  url = 'https://github.com/supermaven-inc/supermaven-nvim',
  main = 'supermaven-nvim',
  cond = function()
    local cwd = vim.uv.cwd()
    return cwd ~= vim.uv.os_homedir()
  end,
  opts = {
    log_level = 'off',
    keymaps = {
      accept_suggestion = '<M-]>',
      clear_suggestion = '<M-[>',
      accept_word = '<M-f>',
    },
  },
}
