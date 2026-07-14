local MACRO_REGS = 'abcdefghijklmnopqrstuvwxyz'

local function get_macros()
  local results = {}
  for i = 1, #MACRO_REGS do
    local reg = MACRO_REGS:sub(i, i)
    local content = vim.fn.getreg(reg)
    if content ~= '' then
      local display = content:gsub('%c', function(c)
        local byte = string.byte(c)
        if byte == 27 then return '<Esc>' end
        if byte == 13 then return '<CR>' end
        if byte == 10 then return '<NL>' end
        if byte < 32 then return '<C-' .. string.char(byte + 64) .. '>' end
        return string.format('<%d>', byte)
      end)
      table.insert(results, { reg = reg, content = content, display = display })
    end
  end
  return results
end

local M = {}

function M.open(opts)
  opts = opts or {}
  local macros = get_macros()

  if #macros == 0 then
    vim.notify('没有已录制的宏', vim.log.levels.INFO)
    return
  end

  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local action_state = require('telescope.actions.state')

  pickers.new(opts, {
    prompt_title = 'CR:exec  C-n:execN  C-e:edit  C-d:del',
    finder = finders.new_table({
      results = macros,
      entry_maker = function(entry)
        return {
          value = entry,
          display = '@' .. entry.reg .. '  ' .. entry.display,
          ordinal = entry.reg .. ' ' .. entry.display,
        }
      end,
    }),
    sorter = conf.generic_sorter(opts),
    previewer = false,
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if entry then
          vim.cmd('normal! @' .. entry.value.reg)
        end
      end)

      map({ 'i', 'n' }, '<C-n>', function()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        actions.close(prompt_bufnr)
        local reg = entry.value.reg
        vim.ui.input({ prompt = '执行 @' .. reg .. ' 次数: ' }, function(input)
          local n = tonumber(input)
          if n and n > 0 then
            vim.cmd('normal! ' .. n .. '@' .. reg)
          end
        end)
      end)

      map({ 'i', 'n' }, '<C-e>', function()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        actions.close(prompt_bufnr)
        local reg = entry.value.reg
        local content = vim.fn.getreg(reg)
        vim.ui.input({ prompt = '编辑 @' .. reg .. ': ', default = content }, function(new)
          if new and new ~= '' then
            vim.fn.setreg(reg, new)
            vim.notify('已更新 @' .. reg, vim.log.levels.INFO)
          end
        end)
      end)

      map({ 'i', 'n' }, '<C-d>', function()
        local entry = action_state.get_selected_entry()
        if not entry then return end
        vim.fn.setreg(entry.value.reg, '')
        vim.notify('已删除 @' .. entry.value.reg, vim.log.levels.INFO)
        actions.close(prompt_bufnr)
      end)

      return true
    end,
  }):find()
end

return M
