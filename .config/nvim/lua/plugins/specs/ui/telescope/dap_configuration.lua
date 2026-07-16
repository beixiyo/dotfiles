-- DAP 配置选择器的关键字高亮
local M = {}

local keywords = {
  { pattern = 'electron', highlight = 'DiagnosticWarn' },
  { pattern = 'bun', highlight = 'DiagnosticInfo' },
  { pattern = 'browser', highlight = 'DiagnosticInfo' },
  { pattern = 'chrome', highlight = 'DiagnosticInfo' },
  { pattern = 'node', highlight = 'DiagnosticOk' },
  { pattern = 'package%.json', highlight = 'DiagnosticHint' },
  { pattern = 'script', highlight = 'DiagnosticHint' },
}

local function highlights(text)
  local result = {}
  local lower = text:lower()

  for _, keyword in ipairs(keywords) do
    local start = 1
    while true do
      local first, last = lower:find(keyword.pattern, start)
      if not first then break end

      table.insert(result, { { first - 1, last }, keyword.highlight })
      start = last + 1
    end
  end

  return result
end

function M.opts()
  return {
    make_display = function()
      return function(entry)
        local name = entry.value.text.name
        return name, highlights(name)
      end
    end,
    make_ordinal = function(entry)
      return entry.text.name
    end,
  }
end

return M
