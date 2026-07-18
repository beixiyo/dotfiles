-- Noice 命令行/消息 UI
---@type PackSpec
return {
  desc = '通知与命令行 UI',
  url = 'https://github.com/folke/noice.nvim',
  main = 'noice',
  dependencies = {
    'https://github.com/MunifTanjim/nui.nvim',
    'https://github.com/rcarriga/nvim-notify',
    'beixiyo/vv-icons.nvim',
  },

  ---@type NoiceConfig
  opts = {
    lsp = {
      hover = {
        silent = true,
      },
      override = {
        ['vim.lsp.util.convert_input_to_markdown_lines'] = true,
        ['vim.lsp.util.stylize_markdown'] = true,
      },
    },
    routes = {
      {
        filter = {
          event = 'msg_show',
          any = {
            { find = '%d+L, %d+B' },
            { find = '; after #%d+' },
            { find = '; before #%d+' },
          },
        },
        view = 'mini',
      },
    },
    presets = {
      bottom_search = true,
      command_palette = true,
      long_message_to_split = true,
    },
  },

  ---@param _ PackSpec
  ---@param opts NoiceConfig
  config = function(_, opts)
    require('noice').setup(opts)

    local icons = require('vv-icons')
    vim.keymap.set('n', '<leader>mh', function() require('noice').cmd('all') end, { desc = icons.command_history .. ' Message history' })

    vim.keymap.set('n', '<leader>mc', function()
      require('noice').cmd('all')
      vim.schedule(function()
        vim.defer_fn(function()
          local target_win = nil
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.api.nvim_win_is_valid(win) then
              local b = vim.api.nvim_win_get_buf(win)
              local ft = vim.bo[b].filetype
              if ft == 'noice' then target_win = win; break end
            end
          end

          if not target_win then
            vim.notify('未找到 Noice 消息窗口，请确认已成功打开', vim.log.levels.WARN)
            return
          end

          local buf = vim.api.nvim_win_get_buf(target_win)
          local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

          if #lines > 0 then
            local filtered = {}
            for _, line in ipairs(lines) do
              if line:match('%S') and not line:match('^[│┌┐└┘├┤┬┴╭╮╰╯]') then
                table.insert(filtered, line)
              end
            end

            if #filtered > 0 then
              local text = table.concat(filtered, '\n')
              vim.fn.setreg('"', text)
              if vim.fn.has('clipboard') == 1 then vim.fn.setreg('+', text) end
              if vim.api.nvim_win_is_valid(target_win) then
                pcall(vim.api.nvim_win_close, target_win, false)
              end
              vim.notify(string.format('已复制 %d 行消息历史到剪贴板', #filtered), vim.log.levels.INFO)
              return
            end
          end

          vim.notify('已打开 noice 消息窗口，请按 ggVG 选中全部内容，然后按 y 复制', vim.log.levels.INFO)
        end, 500)
      end)
    end, { desc = icons.copy .. ' Copy message history' })
  end,
}
