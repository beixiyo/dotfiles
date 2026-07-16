-- vv-git.nvim — git 多功能 TUI（当前含 diff 双栏视图，后续扩展 log/branch/blame 等）
---@type PackSpec
return {
  desc = 'VSCode 风格 Git 面板',
  url  = 'beixiyo/vv-git.nvim',
  main = 'vv-git',
  dependencies = { 'beixiyo/vv-utils.nvim', 'beixiyo/vv-icons.nvim' },

  cmd = {
    'VVGit',
    'VVGitClose',
    'VVGitToggle',
    'VVGitTogglePanel',
    'VVGitRefresh',
    'VVGitCompare',
    'VVGitCompareRef',
    'VVGitCompareRefs',
    'VVGitCompareFile',
    'VVGitCompareStop',
    'VVGitCommitShow',
    'VVGitWorktree',
    'VVGitShow',
    'VVGitSubrepoDepth',
    'VVGitLoad',
  },
  keys = function()
    local icons = require('vv-icons')
    return {
      { '<leader>gd', '<cmd>VVGitToggle<cr>',     desc = icons.git_diff .. ' vv-git' },
      { '<leader>gH', '<cmd>VVGitCompare<cr>',    desc = icons.git_diff .. ' Compare HEAD with commit' },
      { '<leader>gc', '<cmd>VVGitCommitShow<cr>', desc = icons.git_diff .. ' Show commit diff' },
    }
  end,

  ---@type VVGitConfig
  opts = {
    fold_staged = true, -- 打开面板时默认折叠 Staged Changes section（仅此一层）
    diff_ratio = { 4, 6 },
    diff_nowrap = false,
    mappings = {
      -- t：在光标节点目录开/切换浮动终端（目录用自身，文件用父目录），cwd 跟随光标
      ['t'] = function()
        local dir = require('vv-git').get_node_dir()
        if not dir then return end
        require('tools.term').open_at(dir)
      end,
    },
  },
}
