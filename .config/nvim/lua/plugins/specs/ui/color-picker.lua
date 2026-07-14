-- 颜色选择器（Rust GUI 色盘 + 透明度，类 Chrome DevTools）
-- UIEnter：UI 就绪后加载 + 后台下载 Rust 二进制；按 <leader>cp 时已就绪
---@type PackSpec
return {
  desc = '颜色选择器 (GUI)',
  url = 'https://github.com/eero-lehtinen/oklch-color-picker.nvim',
  main = 'oklch-color-picker',
  dependencies = { 'beixiyo/vv-icons.nvim' },
  event = { 'UIEnter' },

  ---@type oklch.Opts
  opts = {
    highlight = {
      enabled = true,
      -- bigfile：vv-utils.bigfile 把大文件 ft 标成 'bigfile' 时跳过着色
      -- oklch 自己的 FileType autocmd 会响应这个变更，主动 clear 已挂的高亮
      ignore_ft = { 'blink-cmp-menu', 'bigfile' },
    },
  },

  ---@param _ PackSpec
  ---@param opts oklch.Opts
  config = function(_, opts)
    require('oklch-color-picker').setup(opts)
    local icons = require('vv-icons')
    vim.keymap.set('n', '<leader>cp', function()
      require('oklch-color-picker').pick_under_cursor()
    end, { desc = icons.ns.kinds.Color .. ' Pick color' })
  end,
}
