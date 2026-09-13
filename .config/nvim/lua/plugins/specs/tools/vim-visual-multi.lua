-- 多光标（vim-visual-multi）
-- 不走 main（main=false）：vim-visual-multi 是 viml 插件，没有 lua 入口
-- vim.g.VM_maps 必须在 packadd 前设置，所以放 init 里
--
-- 缺少原生 API 时自动启用；0.13 使用 config.keymaps.multicursor
-- cond 在下载前过滤，避免两套多光标机制同时加载
---@type PackSpec
return {
  cond = function() return not vim.api.nvim_mcursor end,
  desc = '多光标编辑',
  url = 'https://github.com/mg979/vim-visual-multi',
  main = false,
  dependencies = { 'beixiyo/vv-icons.nvim' },

  init = function()
    vim.g.VM_maps = vim.tbl_extend('force', vim.g.VM_maps or {}, {
      ['Find Under'] = '<C-d>',
      ['Find Subword Under'] = '<C-d>',
      ['Select All'] = '<C-S-l>',
      ['Visual All'] = '<C-S-l>',
      ['Mouse Cursor'] = '<A-leftmouse>',
      ['Add Cursor Down'] = '<C-Down>',
      ['Add Cursor Up'] = '<C-Up>',
    })

    local grp = vim.api.nvim_create_augroup('VM_illuminate', { clear = true })
    vim.api.nvim_create_autocmd('User', {
      pattern = 'visual_multi_start',
      group = grp,
      callback = function() vim.cmd('IlluminatePause') end,
    })
    vim.api.nvim_create_autocmd('User', {
      pattern = 'visual_multi_exit',
      group = grp,
      callback = function() vim.cmd('IlluminateResume') end,
    })
  end,
}
