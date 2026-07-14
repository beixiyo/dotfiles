-- 主题：本地 tokyonight.nvim fork（配色/折叠样式/context 边界等在 fork 源码里改）
-- 配色生效必须 eager，不能懒加载（启动即渲染）
---@type PackSpec
return {
  desc = '主题 (TokyoNight fork)',
  dir = vim.fn.stdpath('config') .. '/vendors/tokyonight.nvim',
  main = 'tokyonight',

  config = function()
    -- 风格: pretty_dark (自定义) | storm | night | moon | day
    require('tokyonight').load(--[[@as tokyonight.Config]] { style = 'pretty_cat' })
  end,
}
