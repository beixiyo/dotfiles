-- 会话管理（auto-session）
---@type PackSpec
return {
  desc = '会话保存与恢复',
  url = 'https://github.com/rmagatti/auto-session',
  main = 'auto-session',

  config = function()
    local dap_breakpoints = require('plugins.specs.tools.session.breakpoints')

    -- session 要保存/恢复的内容：只保留"重新打开项目时真正想恢复"的东西
    -- 已移除的踩坑项：
    --   localoptions —— 会存 buffer 局部映射，导致旧键绑定"阴魂不散"
    --   folds        —— 折叠状态与 LSP/TS 动态折叠冲突
    vim.opt.sessionoptions = 'buffers,curdir,tabpages,winsize'

    ---@type AutoSession.Config
    require('auto-session').setup({
      log_level = 'error',
      suppressed_dirs = { '~/Downloads', '/' },
      root_dir = vim.fn.stdpath('data') .. '/sessions/',
      enabled = true,
      auto_save = true,
      auto_restore = true,
      auto_create = true,
      bypass_save_filetypes = { 'alpha', 'dashboard' },
      git_use_branch_name = true,
      close_unsupported_windows = true,
      save_extra_data = dap_breakpoints.save,
      restore_extra_data = dap_breakpoints.restore,
      pre_restore_cmds = {
        dap_breakpoints.clear,
      },
      -- 保存 session 前关掉 vv-git：它的 tabpage 是临时 UI 容器，
      -- 存下来反而会污染下次启动（nofile 面板存不进去，只残留主 buffer）
      pre_save_cmds = {
        function() pcall(function() require('vv-git').close() end) end,
      },
      session_lens = {
        picker = 'telescope',
        load_on_setup = true,
        previewer = 'summary',
      },
    })
  end,
}
