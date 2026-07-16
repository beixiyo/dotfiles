-- package.json scripts picker 的双列高亮
local M = {}

function M.opts()
  return {
    make_indexed = function(items)
      local strings = require('plenary.strings')
      local indexed = {}
      local widths = { name = 0 }

      for index, item in ipairs(items) do
        table.insert(indexed, {
          idx = index,
          text = item,
          name = item.name,
          command = item.command,
        })
        widths.name = math.max(widths.name, strings.strdisplaywidth(item.name))
      end

      return indexed, widths
    end,
    make_displayer = function(widths)
      return require('telescope.pickers.entry_display').create({
        separator = '  ',
        items = {
          { width = widths.name },
          { remaining = true },
        },
      })
    end,
    make_display = function(displayer)
      return function(entry)
        return displayer({
          { entry.value.name, 'TelescopeResultsIdentifier' },
          entry.value.command,
        })
      end
    end,
    make_ordinal = function(entry)
      return entry.name .. ' ' .. entry.command
    end,
  }
end

return M
