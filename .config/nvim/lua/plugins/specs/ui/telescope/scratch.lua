-- 临时草稿浏览器：按创建时间倒序浏览 scratch 目录里仍在磁盘上的草稿
-- 空文件单独标出，配合 <C-d> 顺手清理；回车走 telescope 默认的打开动作
local M = {}

local Keys = require('vv-utils.keys')

local function ensure_hl()
  vim.api.nvim_set_hl(0, 'VVScratchToday', { link = 'DiagnosticOk', default = true })
  vim.api.nvim_set_hl(0, 'VVScratchWeek', { link = 'DiagnosticInfo', default = true })
  vim.api.nvim_set_hl(0, 'VVScratchOlder', { link = 'Comment', default = true })
  vim.api.nvim_set_hl(0, 'VVScratchEmpty', { link = 'DiagnosticWarn', default = true })
end

local function age_hl(timestamp)
  local age = os.time() - timestamp
  if age < 24 * 60 * 60 then
    return 'VVScratchToday'
  end
  if age < 7 * 24 * 60 * 60 then
    return 'VVScratchWeek'
  end
  return 'VVScratchOlder'
end

function M.open(opts)
  ensure_hl()
  opts = opts or {}

  local Scratch = require('config.scratch')
  local action_state = require('telescope.actions.state')
  local conf = require('telescope.config').values
  local entry_display = require('telescope.pickers.entry_display')
  local finders = require('telescope.finders')
  local pickers = require('telescope.pickers')
  local previewers = require('telescope.previewers')
  local entries = Scratch.list()

  if #entries == 0 then
    vim.notify('No scratch files found', vim.log.levels.INFO)
    return
  end

  local displayer = entry_display.create({
    separator = '  ',
    items = {
      { width = 19 },
      { width = 16 },
      { remaining = true },
    },
  })

  local function make_entry(item)
    local size = item.empty and 'empty' or ('%d B'):format(item.size)
    local size_hl = item.empty and 'VVScratchEmpty' or 'TelescopeResultsComment'
    return {
      display = function()
        return displayer({
          { os.date('%Y-%m-%d %H:%M:%S', item.timestamp), age_hl(item.timestamp) },
          { ('%s · %s'):format(size, item.ext), size_hl },
          item.name,
        })
      end,
      ordinal = table.concat({ item.name, size, os.date('%F %T', item.timestamp) }, ' '),
      path = item.path,
      value = item,
    }
  end

  local previewer = previewers.new_buffer_previewer({
    title = 'Scratch Preview',
    dyn_title = function(_, entry)
      return entry.value.name
    end,
    -- 按路径复用 preview buffer，同一条目来回切换不重复读盘
    get_buffer_by_name = function(_, entry)
      return entry.value.path
    end,
    define_preview = function(self, entry)
      -- bufname 必须是 preview buffer 当前已加载的名字，telescope 用它判断是否需要重新读文件；
      -- 传入目标路径本身会被当成“已加载”而直接跳过读取
      conf.buffer_previewer_maker(entry.value.path, self.state.bufnr, {
        bufname = self.state.bufname,
        winid = self.state.winid,
      })
    end,
  })

  pickers
    .new(opts, {
      prompt_title = table.concat({
        Keys.hint('Open', '<CR>'),
        Keys.hint('Yank text', '<M-y>'),
        Keys.hint('Yank path', '<C-y>'),
        Keys.hint('Delete', '<C-d>'),
      }, '  '),
      finder = finders.new_table({ results = entries, entry_maker = make_entry }),
      previewer = previewer,
      sorter = conf.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, map)
        map({ 'i', 'n' }, '<C-y>', function()
          local entry = action_state.get_selected_entry()
          if not entry then
            return
          end

          vim.fn.setreg('+', entry.value.path)
          vim.notify('Copied path: ' .. entry.value.name, vim.log.levels.INFO)
        end)

        map({ 'i', 'n' }, '<M-y>', function()
          local entry = action_state.get_selected_entry()
          if not entry then
            return
          end

          local ok, lines = pcall(vim.fn.readfile, entry.value.path)
          if not ok then
            vim.notify('Read failed: ' .. entry.value.name, vim.log.levels.ERROR)
            return
          end
          vim.fn.setreg('+', table.concat(lines, '\n'))
          vim.notify(('Copied %d lines: %s'):format(#lines, entry.value.name), vim.log.levels.INFO)
        end)

        map({ 'i', 'n' }, '<C-d>', function()
          local entry = action_state.get_selected_entry()
          if not entry then
            return
          end

          if vim.fn.confirm(('Delete scratch %s?'):format(entry.value.name), '&Yes\n&No', 2) ~= 1 then
            return
          end

          -- delete_selection 会把回调返回 true 的条目从结果里移除并原地刷新，不用关掉重开
          action_state.get_current_picker(prompt_bufnr):delete_selection(function(selection)
            local ok, err = Scratch.delete(selection.value.path)
            if not ok then
              vim.notify('Delete failed: ' .. err, vim.log.levels.ERROR)
              return false
            end

            vim.notify('Scratch deleted: ' .. selection.value.name, vim.log.levels.INFO)
            return true
          end)
        end)

        return true
      end,
    })
    :find()
end

return M
