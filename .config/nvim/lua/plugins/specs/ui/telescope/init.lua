-- telescope.nvim：通用 picker（7 个入口：recent/buffers/keymaps/marks/jumps/cmd history/config files）
-- 布局：全屏水平，左侧 ~40 列（prompt+list），右侧预览占剩余
-- C sorter 由 telescope-fzf-native 提供（FFI），pcall load_extension 兜底
-- 检查 fzf-native 是否启用: lua print(require('telescope').extensions.fzf and '✓' or '✗')
---@type PackSpec
return {
  desc = '通用 picker（recent/buffers/keymaps/marks/jumps/cmd history/config files）',
  url = 'https://github.com/nvim-telescope/telescope.nvim',
  main = 'telescope',
  dependencies = {
    'https://github.com/nvim-lua/plenary.nvim',
    -- telescope-ui-select：把 vim.ui.select 接入 telescope
    'https://github.com/nvim-telescope/telescope-ui-select.nvim',
    'beixiyo/vv-icons.nvim',
    'beixiyo/vv-utils.nvim',
  },

  -- event：UIEnter 后加载，保证 lualine 直接 require('telescope.builtin') 不炸
  -- keys：启动期就注册占位 desc，which-key 能立刻识别
  event = { 'UIEnter' },
  keys = function()
    local icons = require('vv-icons')
    return {
      { '<leader>fr', function() require('plugins.specs.ui.telescope.recent').open() end, desc = icons.recent_files .. ' Recent files' },
      { '<leader>fc', function() require('plugins.specs.ui.telescope.toggles').find_files({ cwd = vim.fn.stdpath('config') }) end, desc = icons.config_files .. ' Config files' },
      { '<leader>fb', function() require('telescope.builtin').buffers() end, desc = icons.buffers .. ' Buffers' },
      { '<leader>fh', function() require('telescope.builtin').command_history() end, desc = icons.command_history .. ' Command history' },
      { '<leader>fm', function() require('telescope.builtin').marks() end, desc = icons.marks .. ' Marks' },
      { '<leader>fj', function() require('telescope.builtin').jumplist() end, desc = icons.jumps .. ' Jumps' },
      { '<leader>fk', function() require('telescope.builtin').keymaps() end, desc = icons.keymaps .. ' Keymaps' },
      { '<leader>fM', function() require('plugins.specs.ui.telescope.macro').open(require('telescope.themes').get_dropdown()) end, desc = icons.registers .. ' Macros' },
      { '<leader>f?', function() require('telescope.builtin').builtin() end, desc = icons.tools .. ' Telescope tools' },

      { '<leader>ff', function() require('plugins.specs.ui.telescope.toggles').find_files() end, desc = icons.find_file .. ' Find files' },
      { '<leader>sb', function() require('telescope.builtin').current_buffer_fuzzy_find() end, desc = icons.find_text .. ' Find in buffer' },
      { '<leader>sg', function() require('plugins.specs.ui.telescope.toggles').live_grep() end, desc = icons.find_text .. ' Find text' },
      { '<leader>sh', function() require('telescope.builtin').help_tags() end, desc = icons.commands .. ' Help tags' },
      { '<leader>sw', function() require('telescope.builtin').grep_string() end, mode = { 'n', 'x' }, desc = icons.words .. ' Find word or selection' },
    }
  end,

  config = function()
    local icons = require('vv-icons')
    local telescope = require('telescope')
    local actions = require('telescope.actions')

    telescope.setup({
      defaults = {
        get_selection_window = function()
          local win = vim.api.nvim_get_current_win()
          if not vim.wo[win].winfixbuf then return 0 end
          for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            local cfg = vim.api.nvim_win_get_config(w)
            if w ~= win and cfg.relative == '' and not vim.wo[w].winfixbuf then
              return w
            end
          end
          return 0
        end,

        prompt_prefix = ' ' .. icons.find_file .. '  ',
        selection_caret = '▏ ',
        entry_prefix = '  ',

        layout_strategy = 'horizontal',
        layout_config = {
          horizontal = {
            width = 0.99,
            height = 0.99,
            preview_width = 0.62,
            prompt_position = 'top',
          },
        },
        -- prompt_position=top 下必须 ascending（结果从上往下渲染）
        sorting_strategy = 'ascending',
        winblend = 0,
        borderchars = { '─', '│', '─', '│', '╭', '╮', '╯', '╰' },
        path_display = { truncate = 1 }, -- 左侧窄，长路径截断显示
        file_ignore_patterns = { 'node_modules/', '%.git/' },

        mappings = {
          i = {
            ['<esc>'] = actions.close,
            ['<C-n>'] = actions.move_selection_next,
            ['<C-p>'] = actions.move_selection_previous,
            ['<Up>']  = actions.cycle_history_prev,
            ['<Down>'] = actions.cycle_history_next,
            ['<C-d>'] = actions.preview_scrolling_down,
            ['<C-u>'] = actions.preview_scrolling_up,
            ['<C-e>'] = function(bufnr)
              require('telescope.actions.set').scroll_previewer(bufnr, 0.3)
            end,
            ['<C-y>'] = function(bufnr)
              require('telescope.actions.set').scroll_previewer(bufnr, -0.3)
            end,
          },
          n = {
            ['q']     = actions.close,
            ['<esc>'] = actions.close,
            ['<C-n>'] = actions.move_selection_next,
            ['<C-p>'] = actions.move_selection_previous,
          },
        },
      },
      pickers = {
        -- 单独缩小几个"小数据源"的 preview：命令/keymap/寄存器文字很短，preview 没意义
        command_history = { theme = 'ivy', previewer = false },
        keymaps = { previewer = false },
      },
      extensions = {
        fzf = {
          fuzzy = true,
          override_generic_sorter = true,
          override_file_sorter = true,
          case_mode = 'smart_case',
        },
        -- ui-select：接管 vim.ui.select（code action / gitsigns 菜单 / session picker 等）
        ['ui-select'] = {
          require('telescope.themes').get_dropdown({ previewer = false }),
          specific_opts = {
            ['dap-configuration'] = require('plugins.specs.ui.telescope.dap_configuration').opts(),
            ['package-script'] = require('plugins.specs.ui.telescope.package_script').opts(),
          },
        },
      },
    })

    -- 加载 C sorter；build 未完成时会失败，pcall 兜底，不影响基础功能
    pcall(telescope.load_extension, 'fzf')
    -- 加载 ui-select：副作用是把 vim.ui.select 替换为 telescope 版
    pcall(telescope.load_extension, 'ui-select')
  end,
}
