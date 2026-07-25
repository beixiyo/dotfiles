local Shared = require('plugins.specs.ui.telescope.toggles.shared')

local M = {}

function M.open(base_opts)
  local opts = base_opts or {}
  local state = { hidden = false, no_ignore = false }
  local defs = {
    { key = '<M-h>', field = 'hidden', on = 'hidden', off = 'no-hidden' },
    { key = '<M-i>', field = 'no_ignore', on = 'no-ignore', off = 'gitignore' },
  }
  local base_cmd = opts.find_command
  if not base_cmd then
    if vim.fn.executable('fd') == 1 then
      base_cmd = { 'fd', '--type', 'f', '--color', 'never' }
    elseif vim.fn.executable('fdfind') == 1 then
      base_cmd = { 'fdfind', '--type', 'f', '--color', 'never' }
    elseif vim.fn.executable('rg') == 1 then
      base_cmd = { 'rg', '--files', '--color', 'never' }
    else
      base_cmd = { 'find', '.', '-type', 'f' }
    end
  end

  local supports_flags = not vim.tbl_contains({ 'find', 'where' }, base_cmd[1])
  local cwd = opts.cwd or vim.uv.cwd()
  local cwd_slash = cwd:sub(-1) == '/' and cwd or (cwd .. '/')
  local function make_entry_with_abs(entry_opts)
    local base = require('telescope.make_entry').gen_from_file(entry_opts)
    return function(line)
      local entry = base(line)
      if entry then entry.ordinal = cwd_slash .. entry.ordinal end
      return entry
    end
  end
  local function create_finder()
    local cmd = vim.deepcopy(base_cmd)
    if supports_flags then
      if state.hidden or state.no_ignore then cmd[#cmd + 1] = '--hidden' end
      if state.no_ignore then cmd[#cmd + 1] = '--no-ignore' end
    end
    return require('telescope.finders').new_oneshot_job(cmd, {
      entry_maker = make_entry_with_abs(opts),
      cwd = opts.cwd,
    })
  end

  require('telescope.builtin').find_files(vim.tbl_extend('force', opts, {
    prompt_title = Shared.build_title('Find Files', state, defs),
    entry_maker = make_entry_with_abs(opts),
    attach_mappings = function(prompt_bufnr, map)
      Shared.attach_toggle_mappings(prompt_bufnr, map, state, defs, function()
        return Shared.build_title('Find Files', state, defs)
      end, create_finder)
      return true
    end,
  }))
end

return M
