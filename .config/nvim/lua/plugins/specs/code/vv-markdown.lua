-- vv-markdown：Markdown 列表智能编辑
---@type PackSpec
return {
  desc = 'Markdown 列表智能编辑（续行/自增/自动重排/缩进/勾选）',
  url  = 'beixiyo/vv-markdown.nvim',
  main = 'vv-markdown',
  ft   = { 'markdown' },
  cmd  = {
    'VVMarkdownEnable', 'VVMarkdownDisable', 'VVMarkdownToggle',
    'VVMarkdownRenumber', 'VVMarkdownToggleCheckbox',
  },
  ---@type VVMarkdownConfig
  opts = {},
}
