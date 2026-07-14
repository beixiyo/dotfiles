-- fff.nvim — Rust 编写的极速文件 picker（Smith-Waterman 算法）
-- 不能 lazy：plugin/fff.lua 会在 UIEnter 预先调用 conf.get() 把配置锁死
-- 必须在 UIEnter 之前执行 setup，否则 vim.g.fff 无法生效
---@type PackSpec
return {
  desc = 'Rust 极速文件搜索',
  url = 'https://github.com/dmtrKovalenko/fff.nvim',
  main = 'fff',
  dev = false,
  dependencies = { 'beixiyo/vv-icons.nvim' },
  build = ":lua require('fff.download').download_or_build_binary()",

  ---@type FffConfig
  opts = {
    prompt = '  ',
    title = 'FFF Files',
    lazy_sync = true,           -- 延迟索引到首次打开 picker（避免 UIEnter 提前初始化 conf）
    prompt_vim_mode = true,     -- 输入框支持 N 模式（对齐 telescope）
    layout = {
      -- width 不能设 1：fff 内部 preview_width = terminal_width*0.5
      -- 两侧边框一加总宽 = terminal+1，会把 preview 挤到覆盖 list 右边框
      width = 0.99,
      height = 0.99,
      prompt_position = 'top',
    },
    keymaps = {
      -- 列表移动改用 <C-p> / <C-n>，把 <Up> 让给历史回放（见下）
      move_up = { '<C-p>' },
      move_down = { '<C-n>' },
      preview_scroll_up = { '<C-u>', '<C-y>' },
      preview_scroll_down = { '<C-d>', '<C-e>' },

      -- 多文件批改三件套（VSCode "Search in Files" 等价工作流）：
      --   <Tab>  勾选当前结果（侧边出现 ▊ 标记）
      --   <C-q>  把勾选项（或没勾选时的全部过滤结果）送 quickfix 并关闭 picker
      --   随后 :cdo s/old/new/g | update 批量替换；或 ]q / [q 逐条跳
      toggle_select = '<Tab>',
      send_to_quickfix = '<C-q>',

      -- <Up> 回到上一次查询，到最旧再按会循环回最新（fff 上游的设计）
      cycle_previous_query = '<Up>',
    },
  },

  ---@param _ PackSpec
  ---@param opts FffConfig
  config = function(_, opts)
    require('fff').setup(opts)

    -- 输入框 N 模式补 q → close：fff 只给 list/preview 硬编码了 q，input buffer 没绑
    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'fff_input',
      callback = function(args)
        vim.keymap.set('n', 'q', function() require('fff.picker_ui').close() end,
          { buffer = args.buf, silent = true, noremap = true, desc = 'Close picker' })
      end,
    })

    local icons = require('vv-icons')
    local map = vim.keymap.set
    map('n', '<leader>ff', function() require('fff').find_files() end, { desc = icons.find_file .. ' Find files' })
    map('n', '<leader>sg', function() require('fff').live_grep() end, { desc = icons.find_text .. ' Find text' })
    map('n', '<leader>sw', function() require('fff').live_grep({ query = vim.fn.expand('<cword>') }) end, { desc = icons.words .. ' Find word' })
    map('x', '<leader>sw', function()
      local saved = vim.fn.getreg('v')
      vim.cmd('normal! "vy')
      local query = vim.fn.getreg('v')
      vim.fn.setreg('v', saved)
      require('fff').live_grep({ query = query })
    end, { desc = icons.words .. ' Find selection' })
  end,
}
