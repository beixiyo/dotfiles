-- toggleterm.nvim 终端切换
-- 多终端管理（float / horizontal / vertical / tab）
---@type PackSpec
return {
  desc = '终端切换（float/horizontal/vertical/tab）',
  url = 'https://github.com/akinsho/toggleterm.nvim',
  main = 'toggleterm',

  cmd = { 'ToggleTerm', 'ToggleTermToggleAll', 'TermExec',
    'ToggleTermSendCurrentLine', 'ToggleTermSendVisualLines', 'ToggleTermSendVisualSelection' },

  keys = {
    { '<leader>tt', '<cmd>ToggleTerm<cr>',                        mode = { 'n', 't' }, desc = 'Toggle term' },
    { '<C-@>',      '<cmd>ToggleTerm<cr>',                        mode = { 'n', 't' }, desc = 'Toggle term' },
    { '<leader>tf', '<cmd>ToggleTerm direction=float<cr>',        desc = 'Float term' },
    { '<leader>th', '<cmd>ToggleTerm direction=horizontal<cr>',   desc = 'Horizontal term' },
    { '<leader>tv', '<cmd>ToggleTerm direction=vertical<cr>',     desc = 'Vertical term' },
  },

  ---@type ToggleTermConfig
  opts = {
    size = function(term)
      if term.direction == 'horizontal' then return 15 end
      if term.direction == 'vertical' then return math.floor(vim.o.columns * 0.4) end
      return 20
    end,
    open_mapping = [[<C-@>]],
    hide_numbers = true,
    shade_terminals = true,
    start_in_insert = true,
    insert_mappings = true,
    terminal_mappings = true,
    persist_size = true,
    persist_mode = true,
    direction = 'float',
    close_on_exit = true,
    shell = vim.o.shell,
    auto_scroll = true,
    float_opts = { border = 'curved', winblend = 0, title_pos = 'center' },
    winbar = { enabled = false },
  },

  ---@param _ PackSpec
  ---@param opts ToggleTermConfig
  config = function(_, opts)
    require('toggleterm').setup(opts)

    -- 终端模式内：jk / <esc> 回到 normal；normal 模式下 q 关闭终端
    -- 窗口焦点切换由 smart-splits <C-A-h/j/k/l> 统一处理
    vim.api.nvim_create_autocmd('TermOpen', {
      pattern = 'term://*toggleterm#*',
      callback = function(args)
        local o = { buffer = args.buf, silent = true }

        -- jk 回到 normal 模式
        vim.keymap.set('t', 'jk', [[<C-\><C-n>]], o)
        vim.keymap.set('t', '<esc>', [[<C-\><C-n>]], o)
        vim.keymap.set('n', 'q', '<cmd>ToggleTerm<cr>', o)
      end,
    })
  end,
}
