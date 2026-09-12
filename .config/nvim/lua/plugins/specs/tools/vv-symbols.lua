-- 基于 LSP 的符号树、实时筛选与函数上方引用提示
---@type PackSpec
return {
  desc = 'LSP 符号浏览、实时筛选与引用提示',
  dir = vim.fn.stdpath('config') .. '/vendors/vv-symbols.nvim',
  main = 'vv-symbols',
  dependencies = { 'beixiyo/vv-utils.nvim' },
  event = { 'UIEnter', 'LspAttach' },
  cmd = {
    'VVSymbolsOpen',
    'VVSymbolsClose',
    'VVSymbolsToggle',
    'VVSymbolsFilter',
    'VVSymbolsRefresh',
    'VVSymbolsReferences',
    'VVSymbolsLensEnable',
    'VVSymbolsLensDisable',
    'VVSymbolsEnable',
    'VVSymbolsDisable',
    'VVSymbolsDiagnostics',
    'VVSymbolsQuickfix',
    'VVSymbolsLoclist',
  },
  opts = function()
    return {
      panel = { state = require('vv-utils.state').register('vv-symbols', 'panel') },
      lens = { enabled = true, scope = 'exported' },
    }
  end,
  keys = function()
    local icons = require('vv-icons')
    return {
      {
        '<leader>xx',
        function() require('vv-symbols').diagnostics({ buf = 0, toggle = true }) end,
        desc = icons.list .. ' Buffer diagnostics',
      },
      {
        '<leader>xX',
        function() require('vv-symbols').diagnostics({ toggle = true }) end,
        desc = icons.list .. ' Workspace diagnostics',
      },
      {
        '<leader>xq',
        function() require('vv-symbols').quickfix({ toggle = true }) end,
        desc = icons.list .. ' Quickfix',
      },
      {
        '<leader>xQ',
        function()
          vim.fn.setqflist({}, 'r', {})
          require('vv-symbols').close()
        end,
        desc = icons.list .. ' Clear quickfix',
      },
    }
  end,
  config = function(_, opts)
    require('vv-symbols').setup(opts)

    local group = vim.api.nvim_create_augroup('VVSymbolsNativeQuickfix', { clear = true })

    local function is_quickfix(win)
      if not vim.api.nvim_win_is_valid(win) then return false end
      local info = vim.fn.getwininfo(win)[1]
      return info and info.quickfix == 1, info and info.loclist == 1
    end

    local function source_window(win, loclist)
      local owner
      if loclist then
        owner = vim.fn.getloclist(win, { filewinid = 0 }).filewinid
      else
        owner = vim.fn.win_getid(vim.fn.winnr('#'))
      end
      if type(owner) ~= 'number' or owner <= 0 or owner == win or not vim.api.nvim_win_is_valid(owner) then return end
      local owner_quickfix = is_quickfix(owner)
      if owner_quickfix then return end
      return owner
    end

    vim.api.nvim_create_autocmd('BufWinEnter', {
      group = group,
      callback = function()
        local qf_win = vim.api.nvim_get_current_win()
        local quickfix, loclist = is_quickfix(qf_win)
        if not quickfix then return end
        local owner_win = source_window(qf_win, loclist)
        if not owner_win then return end
        local qf_buf = vim.api.nvim_win_get_buf(qf_win)
        local owner_buf = vim.api.nvim_win_get_buf(owner_win)

        vim.schedule(function()
          local still_quickfix, still_loclist = is_quickfix(qf_win)
          if
            not vim.api.nvim_win_is_valid(qf_win)
            or not still_quickfix
            or still_loclist ~= loclist
            or vim.api.nvim_win_get_buf(qf_win) ~= qf_buf
            or not vim.api.nvim_win_is_valid(owner_win)
            or vim.api.nvim_win_get_buf(owner_win) ~= owner_buf
          then
            return
          end
          vim.api.nvim_win_close(qf_win, true)
          if not vim.api.nvim_win_is_valid(owner_win) then return end
          vim.api.nvim_set_current_win(owner_win)
          local symbols = require('vv-symbols')
          if loclist then
            symbols.loclist({ win = owner_win })
          else
            symbols.quickfix()
          end
        end)
      end,
    })
  end,
}
