-- vv-expand：智能增量选区
-- 扩张优先级: pair(本行成对字符) → LSP selectionRange → treesitter 父节点 → 行
---@type PackSpec
return {
  desc = '智能增量选区',
  url  = 'beixiyo/vv-expand.nvim',
  main = 'vv-expand',
  cmd = { 'VVExpandInit', 'VVExpandExpand', 'VVExpandShrink' },
  event = { 'BufReadPost', 'BufNewFile' },
  loadInVSCode = true,
  ---@type VVExpandConfig
  opts = {
    -- 覆盖默认即可，留空使用默认
    -- pairs = { same = {...}, nested = {...} },
    -- layers = { 'pair', 'lsp', 'treesitter', 'line' },
    -- keymaps = { init = '<CR>', expand = '<CR>', shrink = '<BS>' },
    -- filetype_exclude = { 'qf', 'help', 'dashboard', 'vv-explorer', 'vv-task-panel' },
  },
}
