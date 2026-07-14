-- 多光标（vim-visual-multi）
-- 不走 main（main=false）：vim-visual-multi 是 viml 插件，没有 lua 入口
-- vim.g.VM_maps 必须在 packadd 前设置，所以放 init 里
--
-- 暂用 VM 凑合：现有插件方案在「实时预览 / 补全集成 / 无模态」三者间只能二选一
-- Neovim 官方原生多光标进度（届时可切回原生重新评估）：
--   路线图：https://neovim.io/roadmap/         （0.13 区块的 "Multicursor, super-macros"）
--   跟踪 issue：https://github.com/neovim/neovim/issues/7257  （open/locked，维护者：Still planned, no timeline）
-- 难点本质：Vim 的键输入未「结构化/原子化」，原生多光标得先解决这个（Justin Keyes 访谈），所以慢
---@type PackSpec
return {
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
