-- 图标提供者：mini.icons（vv-explorer / bufferline / telescope 等图标的统一来源）
-- 通过 MiniIcons.mock_nvim_web_devicons() 让依赖 nvim-web-devicons 的插件无感获取
-- 图标字典维护在 vv-icons.nvim/lua/vv-icons/data/*.json（与 zsh/bun 共用）
---@type PackSpec
return {
  desc = '图标提供者（Material 风格）',
  url = 'https://github.com/nvim-mini/mini.icons',
  main = 'mini.icons',
  dependencies = { 'beixiyo/vv-icons.nvim' },

  opts = function()
    local icons = require('vv-icons')
    return {
      style = 'glyph',
      directory = icons.directories,
      file = icons.files,
      extension = icons.extensions,
      filetype = icons.filetypes,
    }
  end,

  config = function(_, opts)
    require('mini.icons').setup(opts)
    -- 让 lualine / bufferline / trouble 等依赖 nvim-web-devicons 的插件统一走 mini.icons
    MiniIcons.mock_nvim_web_devicons()
  end,
}
