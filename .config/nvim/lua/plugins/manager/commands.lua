-- :PluginManager 与 <leader>fp
vim.api.nvim_create_user_command('PluginManager', function()
  require('plugins.manager').open()
end, { desc = '打开可选插件管理（勾选/取消后保存）' })

vim.keymap.set('n', '<leader>fp', '<cmd>PluginManager<cr>', { desc = '可选插件管理' })
