-- VSCode 风格彩虹缩进（vv-indent.nvim）
-- 当前作用域按光标缩进深度循环彩虹色，其它缩进线灰色
---@type PackSpec
return {
  desc = '缩进参考线（彩虹作用域）',
  url  = 'beixiyo/vv-indent.nvim',
  main = 'vv-indent',
  cmd = { 'VVIndentEnable', 'VVIndentDisable', 'VVIndentToggle' },
  event = { 'BufReadPost', 'BufNewFile' },
  ---@type VVIndentConfig
  opts = {},
}
