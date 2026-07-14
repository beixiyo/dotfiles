local icons = require("vv-icons")

local function map(mode, lhs, rhs, opts)
  opts = opts or {}
  if opts.silent == nil then
    opts.silent = true
  end

  local modes = type(mode) == "string" and { mode } or mode
  for _, m in ipairs(modes) do
    pcall(vim.keymap.del, m, lhs)
  end

  vim.keymap.set(mode, lhs, rhs, opts)
end

return { map = map, icons = icons }
