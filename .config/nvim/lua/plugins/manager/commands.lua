-- :PluginManager 与 <leader>fp
vim.api.nvim_create_user_command('PluginManager', function()
  require('plugins.manager').open()
end, { desc = 'Open plugin manager (toggles are saved)' })

vim.keymap.set('n', '<leader>fp', '<cmd>PluginManager<cr>', { desc = 'Plugin Manager' })
