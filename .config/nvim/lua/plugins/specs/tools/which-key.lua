-- which-key 键位提示
---@type PackSpec
return {
  desc = '快捷键提示',
  url = 'https://github.com/folke/which-key.nvim',
  main = 'which-key',
  dependencies = { 'beixiyo/vv-icons.nvim' },

  ---@return wk.Opts
  opts = function()
    local icons = require('vv-icons')
    local terminal_order = {
      n = 10, F = 11, T = 12, o = 13, u = 14, x = 15,
      d = 20,
      t = 30, f = 31, h = 32, v = 33,
      p = 40, l = 41,
      s = 50,
    }

    local function workflow_sort(item)
      local parent = item.node and item.node.parent
      if not parent or parent.keys ~= '<Space>t' then return 1000 end

      return terminal_order[item.raw_key] or 1000
    end

    return {
      preset = 'helix',
      sort = { 'local', workflow_sort, 'group', 'alphanum', 'mod' },
      icons = {
        rules = {
          { pattern = 'debug', icon = icons.debug, color = 'red' },
          { pattern = 'test', icon = icons.test, color = 'green' },
          { pattern = 'horizontal term', icon = icons.split_horizontal, color = 'blue' },
          { pattern = 'vertical term', icon = icons.split_vertical, color = 'blue' },
          { pattern = 'term', icon = icons.terminal, color = 'blue' },
          { pattern = 'task panel', icon = icons.tools, color = 'orange' },
          { pattern = 'task list', icon = icons.list, color = 'blue' },
          { pattern = 'send', icon = icons.copy, color = 'cyan' },
        },
      },
      spec = {
        {
          mode = { 'n', 'x' },
          { '<leader>a', group = 'AI',                  icon = { icon = icons.get('directory', '.claude'), color = 'orange' } },
          { '<leader>c', group = 'code',                icon = { icon = icons.code,        color = 'green'  } },
          { '<leader>b', group = 'buffers',            icon = { icon = icons.buffers,     color = 'blue'   } },
          { '<leader>f', group = 'files & flow',        icon = { icon = icons.find_file,   color = 'blue'   } },
          { '<leader>g', group = 'git',                icon = { icon = icons.git_branches, color = 'red'   } },
          { '<leader>s', group = 'search',             icon = { icon = icons.find_file,   color = 'cyan'   } },
          { '<leader>x', group = 'diagnostics',          icon = { icon = icons.diagnostics, color = 'orange' } },
          { '<leader>d', group = 'debug',              icon = { icon = icons.debug,       color = 'red'    } },
          { '<leader>m', group = 'messages & markdown', icon = { icon = icons.message,     color = 'cyan'   } },
          { '<leader>i', group = 'i18n',               icon = { icon = '󰗊',                color = 'cyan'   } },
          { '<leader>t', group = 'term | task | test | tmux', icon = { icon = icons.terminal,    color = 'blue'   } },
          { '<leader>z', group = 'debug',                     icon = { icon = icons.debug,       color = 'red'    } },

          { '[',  group = 'previous',              icon = { icon = icons.prev,  color = 'grey' } },
          { ']',  group = 'next',                  icon = { icon = icons.next,  color = 'grey' } },
          { 'g',  group = 'goto',                  icon = { icon = icons.jumps, color = 'grey' } },
          { 'gr', group = 'LSP',                   icon = { icon = icons.lsp,   color = 'cyan' } },
          { 'z',  group = 'fold',                  icon = { icon = '󰘖',          color = 'grey' } },
        },
      },
    }
  end,

  ---@param _ PackSpec
  ---@param opts wk.Opts
  config = function(_, opts)
    local icons = require('vv-icons')
    local wk = require('which-key')
    wk.setup(opts)

    vim.keymap.set('n', '<leader>?', function() wk.show({ global = false }) end, { desc = icons.keymaps .. ' Buffer keymaps' })
    vim.keymap.set('n', '<leader>gl', function() require('plugins.specs.ui.telescope.git_log').open() end, { desc = icons.git_log .. ' Git log' })
    vim.keymap.set('n', '<leader>gL', function() require('plugins.specs.ui.telescope.git_buf_log').open() end, { desc = icons.git_log .. ' Buffer git log' })
    vim.keymap.set('n', '<leader>gb', function() require('plugins.specs.ui.telescope.git_branches').open() end, { desc = icons.git_branches .. ' Git branches' })
    vim.keymap.set('n', '<leader>gs', function() require('plugins.specs.ui.telescope.git_stash').open() end, { desc = icons.git_stash .. ' Git stashes' })
    vim.keymap.set('n', '<leader>gt', function() require('plugins.specs.ui.telescope.git_tags').open() end, { desc = icons.git_log .. ' Git tags' })

    -- Stash push 操作（<leader>gS 前缀）
    local stash = function() return require('plugins.specs.ui.telescope.git_stash') end
    vim.keymap.set('n', '<leader>gSp', function() stash().push_all() end,       { desc = 'Stash: push all' })
    vim.keymap.set('n', '<leader>gSs', function() stash().push_staged() end,    { desc = 'Stash: push staged only' })
    vim.keymap.set('n', '<leader>gSu', function() stash().push_untracked() end, { desc = 'Stash: push + untracked' })
    vim.keymap.set('n', '<leader>gSm', function() stash().push_message() end,   { desc = 'Stash: push with message' })

    wk.add({
      { '<leader>gl', icon = { icon = icons.git_branches, color = 'red' } },
      { '<leader>gL', icon = { icon = icons.git_branches, color = 'red' } },
      { '<leader>gb', icon = { icon = icons.git_branches, color = 'orange' } },
      { '<leader>gs', icon = { icon = icons.git_stash, color = 'purple' } },
      { '<leader>gh',  group = 'hunks',                     icon = { icon = icons.git_diff,  color = 'yellow' } },
      { '<leader>gS',  group = 'stash push',                icon = { icon = icons.git_stash, color = 'purple' } },
      { '<leader>gSp', icon = { icon = icons.git_added,   color = 'green'  } },
      { '<leader>gSs', icon = { icon = icons.git_added,   color = 'yellow' } },
      { '<leader>gSu', icon = { icon = icons.git_added,   color = 'cyan'   } },
      { '<leader>gSm', icon = { icon = icons.git_stash,   color = 'purple' } },
    })

    vim.keymap.set('n', '<leader>ds', function()
      local buf = vim.api.nvim_get_current_buf()
      local row = vim.fn.line('.') - 1
      local col = vim.fn.col('.') - 1
      local captures = vim.treesitter.get_captures_at_pos(buf, row, col)

      if captures and #captures > 0 then
        local names = vim.tbl_map(function(c) return c.capture end, captures)
        local hl_name = '@' .. names[1]
        local linked = vim.api.nvim_get_hl(0, { name = hl_name, link = true })
        local direct = vim.api.nvim_get_hl(0, { name = hl_name, link = false })

        vim.notify('capture: ' .. names[1] .. '\nhl: ' .. hl_name .. '\nlink: ' .. vim.inspect(linked) .. '\ndirect: ' .. vim.inspect(direct), vim.log.levels.DEBUG)
      else
        local syn = vim.fn.synIDtrans(vim.fn.synID(vim.fn.line('.'), vim.fn.col('.'), 1))
        local name = vim.fn.synIDattr(syn, 'name')
        local hl = vim.api.nvim_get_hl(0, { name = name, link = false, create = false })

        vim.notify(name .. '\n' .. vim.inspect(hl), vim.log.levels.DEBUG)
      end
    end, { desc = icons.debug .. ' Highlight under cursor' })
  end,
}
