-- fff — Rust 编写的极速文件/内容搜索（Smith-Waterman + 内存索引 + 后台 watcher）
-- grep 模式原生按文件分组：文件名组头 + treesitter 语法着色 + 匹配高亮（p200 压语法 p120）
-- 匹配色使用 fff 默认的 IncSearch，由主题定义
-- <leader>ff / <leader>sg / <leader>sw 归属本插件；telescope 侧同键位实现已摘除（见 telescope/init.lua 注释，可回退）
-- 辅助模块：query.lua（query 分词 / 路径→glob）、filter_input.lua（<M-p> 筛选弹窗）、scope.lua（按路径限定搜索）、
--          grep_renderer.lua（grep 列表裁掉前导缩进）
-- 迁移状态与后续计划见同目录 MIGRATION.md
-- 不能 lazy：plugin/fff.lua 会在 UIEnter 预先调用 conf.get() 把配置锁死
-- 必须在 UIEnter 之前执行 setup，否则 vim.g.fff 无法生效
---@type PackSpec
return {
  desc = 'Rust 极速文件搜索 + 分组 grep',
  url = 'https://github.com/dmtrKovalenko/fff',
  main = 'fff',
  dev = false,
  dependencies = { 'beixiyo/vv-icons.nvim', 'beixiyo/vv-utils.nvim' },
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
      -- 方向键与 <C-p>/<C-n> 等价做列表移动；历史回放用 <C-Up>/<C-Down>（与 telescope 侧统一）
      move_up = { '<Up>', '<C-p>' },
      move_down = { '<Down>', '<C-n>' },
      preview_scroll_up = { '<C-u>', '<C-y>' },
      preview_scroll_down = { '<C-d>', '<C-e>' },

      -- 多文件批改三件套（VSCode "Search in Files" 等价工作流）：
      --   <Tab>  勾选当前结果（侧边出现 ▊ 标记）
      --   <C-q>  把勾选项（或没勾选时的全部过滤结果）送 quickfix 并关闭 picker
      --   随后 :cdo s/old/new/g | update 批量替换；或 ]q / [q 逐条跳
      toggle_select = '<Tab>',
      send_to_quickfix = '<C-q>',

      -- <C-Up> 回到上一次查询，到最旧再按会循环回最新（fff 上游的设计）；<C-Down> 往新的方向走
      cycle_previous_query = '<C-Up>',
      cycle_forward_query = '<C-Down>',
    },
  },

  ---@param _ PackSpec
  ---@param opts FffConfig
  config = function(_, opts)
    -- fff 配置里 mappings 与 keymaps 平级（顶层字段，仅作用于输入框）
    opts.mappings = { i = { ['<M-p>'] = require('plugins.specs.tools.fff.filter_input').open } }

    require('fff').setup(opts)

    -- 输入框 N 模式补 q → close：fff 只给 list/preview 硬编码了 q，input buffer 没绑
    vim.api.nvim_create_autocmd('FileType', {
      pattern = 'fff_input',
      callback = function(args)
        vim.keymap.set('n', 'q', function() require('fff.picker_ui').close() end,
          { buffer = args.buf, silent = true, noremap = true, desc = 'Close picker' })
      end,
    })

    -- preview 启用 treesitter：fff 只给 preview 设 filetype，高亮依赖 FileType 回调；
    -- code/treesitter.lua 跳过 buftype≠'' 的 buffer，而 preview 是 nofile scratch buffer，
    -- 于是除 lua 等 nvim 内置 ftplugin 自带 TS 的语言外都退回 regex syntax（颜色寡淡）
    -- 只对已装 parser 的语言启动、不触发安装；无 parser 时 stop，避免上一个文件的高亮残留
    vim.api.nvim_create_autocmd('FileType', {
      group = vim.api.nvim_create_augroup('FFFPreviewTreesitter', { clear = true }),
      callback = function(args)
        local buf = args.buf
        if buf ~= require('fff.picker_ui.picker_ui_state').state.preview_buf then return end

        local lang = vim.treesitter.language.get_lang(args.match) or args.match
        local bytes = vim.api.nvim_buf_get_offset(buf, vim.api.nvim_buf_line_count(buf))
        local ok, has_parser = pcall(vim.treesitter.language.add, lang)
        if args.match == '' or bytes > 100 * 1024 or not (ok and has_parser)
          or not pcall(vim.treesitter.start, buf, lang) then
          pcall(vim.treesitter.stop, buf)
        end
      end,
    })

    local icons = require('vv-icons')
    local map = vim.keymap.set
    map('n', '<leader>ff', function() require('fff').find_files() end, { desc = icons.find_file .. ' Find files' })
    -- grep 入口统一带自定义 renderer（列表裁掉匹配行前导缩进，见 grep_renderer.lua）
    local grep_opts = { renderer = require('plugins.specs.tools.fff.grep_renderer') }
    map('n', '<leader>sg', function() require('fff').live_grep(grep_opts) end, { desc = icons.find_text .. ' Find text' })
    -- 选区/光标词搜索：fff 原生 live_grep_under_cursor 自带 n（cword）/ x（选区，getregion 无寄存器副作用）两种模式
    map({ 'n', 'x' }, '<leader>sw', function() require('fff').live_grep_under_cursor(grep_opts) end, { desc = icons.words .. ' Find word' })
    map('x', '<leader>sg', function() require('fff').live_grep_under_cursor(grep_opts) end, { desc = icons.find_text .. ' Search selection' })
  end,
}
