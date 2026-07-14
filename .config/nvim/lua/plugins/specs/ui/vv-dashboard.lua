-- 自实现启动页（零外部依赖）
-- 不 lazy：需要在 VimEnter 之前 setup 才能挂 auto_open 钩子
---@type PackSpec
return {
  desc = '自实现启动页',
  url  = 'beixiyo/vv-dashboard.nvim',
  main = 'vv-dashboard',
  dependencies = { 'beixiyo/vv-utils.nvim', 'beixiyo/vv-icons.nvim' },
  -- 不加 cmd/keys/event：此插件必须 eager load，VimEnter 前 setup 才能挂 auto_open

  ---@return VVDashboardConfig
  opts = function()
    local icons = require('vv-icons')
    return {
      filetype = 'dashboard', -- 与 vv-explorer 的 close_on_filetype 默认对齐

      keys = {
        { icon = icons.find_file,    key = 'f', desc = 'Find File', action = function() require('telescope.builtin').find_files() end },
        { icon = icons.new_file,     key = 'n', desc = 'New File', action = ':ene | startinsert' },
        { icon = icons.find_text,    key = 'g', desc = 'Find Text', action = function() require('telescope.builtin').live_grep() end },
        { icon = icons.recent_files, key = 'r', desc = 'Recent Files', action = function() require('telescope.builtin').oldfiles() end },
        { icon = icons.config,       key = 'c', desc = 'Config Files', action = function() require('telescope.builtin').find_files({ cwd = vim.fn.stdpath('config') }) end },
        { icon = icons.tools,        key = 'p', desc = 'Plugin Manager', action = ':PluginManager' },
        { icon = icons.quit,         key = 'q', desc = 'Quit', action = ':qa' },
      },

      -- 单行多色 footer：Neovim loaded X/Y plugins in N.NNms
      footer = function()
        local s = _G.PackStats or {}
        local loaded = #(s.plugins or {})
        local total = s.registered or loaded
        return {
          { '⚡ ',                               'Special' },
          { 'NeoVim',                           'Keyword' },
          { ' loaded ',                         'Comment' },
          { tostring(loaded),                   'Constant' },
          { '/',                                'Comment' },
          { tostring(total),                    'Number' },
          { ' plugins in ',                     'Comment' },
          { ('%.2fms'):format(s.total_ms or 0), 'Constant' },
        }
      end,
    }
  end,
}
