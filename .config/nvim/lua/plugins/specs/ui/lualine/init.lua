-- 状态栏（lualine.nvim）
-- UIEnter 后加载：dashboard 期间禁用 statusline，无视觉差
-- 子模块：./theme（tokyonight pretty_dark 适配）/ ./components（组件）/ ./actions（点击交互）
---@type PackSpec
return {
  desc = '状态栏',
  url = 'https://github.com/nvim-lualine/lualine.nvim',
  main = 'lualine',
  dependencies = {
    'https://github.com/nvim-tree/nvim-web-devicons',
    'beixiyo/vv-icons.nvim',  -- components.lua 顶部 require
    'beixiyo/vv-utils.nvim',  -- components.lua 用 path / hl
  },

  event = { 'UIEnter' },

  config = function()
    local lualine_require = require('lualine_require')
    lualine_require.require = require

    local theme = require('plugins.specs.ui.lualine.theme')
    local c     = require('plugins.specs.ui.lualine.components')

    vim.api.nvim_create_autocmd({ 'RecordingEnter', 'RecordingLeave' }, {
      group = vim.api.nvim_create_augroup('lualine_macro', { clear = true }),
      callback = function()
        vim.schedule(function() vim.cmd('redrawstatus') end)
      end,
    })

    require('lualine').setup({
      options = {
        theme = theme,
        globalstatus = true,
        disabled_filetypes = { statusline = { 'dashboard', 'alpha', 'ministarter' } },
        component_separators = { left = '', right = '' },
        section_separators   = { left = '\u{e0b4}', right = '\u{e0b6}' },
      },
      sections = {
        lualine_a = { c.mode() },
        lualine_b = { c.branch() },
        lualine_c = {
          c.root_dir(),
          c.diagnostics(),
          c.pretty_path(),
        },
        lualine_x = {
          c.lsp(),
          c.noice_command(),
          c.dap(),
          c.diff(),
        },
        lualine_y = {
          c.progress(),
          c.location(),
        },
        lualine_z = {
          c.clock(),
        },
      },
      extensions = { 'fzf' },
    })
  end,
}
