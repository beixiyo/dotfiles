-- Git 行内标记 & hunk 操作
---@type PackSpec
return {
  desc = 'Git 行内标记与 hunk 操作',
  url = 'https://github.com/lewis6991/gitsigns.nvim',
  main = 'gitsigns',
  dependencies = {
    'https://github.com/nvim-lua/plenary.nvim',
    'beixiyo/vv-icons.nvim',
  },

  ---@type Gitsigns.Config
  opts = {
    signs = {
      add = { text = '▎' },
      change = { text = '▎' },
      delete = { text = '󰍵' },
      topdelete = { text = '󰍵' },
      changedelete = { text = '▎' },
      untracked = { text = '┆' },
    },
    signs_staged = {
      add = { text = '▎' },
      change = { text = '▎' },
      delete = { text = '󰍵' },
      topdelete = { text = '󰍵' },
      changedelete = { text = '▎' },
      untracked = { text = '┆' },
    },
    signcolumn = false, -- 关闭左侧线条展示，使用 status colmun 插件
    numhl = false,
    linehl = false,
    word_diff = false,
    current_line_blame = false,
    current_line_blame_opts = { delay = 800, virt_text_pos = 'eol' },
    on_attach = function(bufnr)
      local gs = package.loaded.gitsigns
      if not gs then return end

      local icons = require('vv-icons')
      local map = function(mode, lhs, rhs, desc, icon_key)
        local icon = icons[icon_key or 'git_status'] or icons.git_status
        vim.keymap.set(mode, lhs, rhs, { desc = icon .. ' ' .. desc, buffer = bufnr })
      end

      -- 跳转：]c / [c 与 Vim 原生 diff 跳转键一致；已在 diff 窗口则走原生行为
      map('n', ']c', function()
        if vim.wo.diff then
          vim.cmd.normal({ ']c', bang = true })
        else
          gs.nav_hunk('next')
        end
      end, 'Next hunk', 'next')

      map('n', '[c', function()
        if vim.wo.diff then
          vim.cmd.normal({ '[c', bang = true })
        else
          gs.nav_hunk('prev')
        end
      end, 'Previous hunk', 'prev')

      -- 暂存 / 重置
      map({ 'n', 'v' }, '<leader>ghs', gs.stage_hunk, 'Stage hunk', 'git_added')
      map({ 'n', 'v' }, '<leader>ghr', gs.reset_hunk, 'Reset hunk', 'git_removed')
      map('n', '<leader>ghS', gs.stage_buffer, 'Stage buffer', 'git_added')
      map('n', '<leader>ghR', gs.reset_buffer, 'Reset buffer', 'git_removed')

      -- 预览
      map('n', '<leader>ghp', gs.preview_hunk, 'Preview hunk', 'git_diff')
      -- 行内预览：用 virtual text 原地展示 diff，不弹浮窗，适合快速瞄一眼当前改动
      map('n', '<leader>ghi', gs.preview_hunk_inline, 'Preview hunk inline', 'git_diff')

      -- Blame
      map('n', '<leader>ghB', gs.blame_line, 'Blame line', 'git_log')
      map('n', '<leader>ghBF', function() gs.blame_line({ full = true }) end, 'Blame line details', 'git_log')

      -- Diff 整个 buffer（开新窗口对比）
      -- ghd：当前 buffer vs index（已暂存状态），看的是「工作区里还没 git add 的改动」
      map('n', '<leader>ghd', gs.diffthis, 'Diff against index', 'git_diff')
      -- ghD：当前 buffer vs HEAD~1（上一次提交的前一个），看的是「本次提交包含的所有改动」
      map('n', '<leader>ghD', function() gs.diffthis('~') end, 'Diff against HEAD~', 'git_diff')

      -- Quickfix：把 hunk 列到 quickfix 窗口，用 :cn/:cp 或 quickfix UI 批量跳转
      -- ghq：仅当前 buffer 的 hunk
      map('n', '<leader>ghq', gs.setqflist, 'Buffer hunks', 'list')
      -- ghQ：整个仓库所有已修改文件的 hunk（跨文件 review 改动时用）
      map('n', '<leader>ghQ', function() gs.setqflist('all') end, 'Repository hunks', 'list')

      -- Toggles：临时开关视觉提示，默认是关的
      -- ghtb：行尾虚拟文本显示「谁、多久前、改了啥」，看历史追责时开一下
      map('n', '<leader>ghtb', gs.toggle_current_line_blame, 'Toggle line blame', 'git_log')
      -- ghtw：词级别 diff 高亮，标出同一行里具体哪几个字符/单词变了
      map('n', '<leader>ghtw', gs.toggle_word_diff, 'Toggle word diff', 'git_diff')

      -- Text object：把 hunk 当成文本对象，配合操作符使用
      -- vih 选中整个 hunk、dih 删掉、yih 复制、cih 替换
      map({ 'o', 'x' }, 'ih', gs.select_hunk, 'Select hunk', 'git_modified')
    end,
  },
}
