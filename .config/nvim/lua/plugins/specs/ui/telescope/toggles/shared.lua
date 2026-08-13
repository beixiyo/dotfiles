local Glob = require('vv-utils.glob')
local Keys = require('vv-utils.keys')
local PathCompletion = require('vv-utils.path_completion')

local M = {}

local completion_id = 0

function M.grep_defs()
  return {
    { key = '<M-h>', field = 'hidden', on = 'hidden', off = 'no-hidden' },
    { key = '<M-i>', field = 'no_ignore', on = 'no-ignore', off = 'gitignore' },
    { key = '<M-f>', field = 'fixed_strings', on = 'Fixed-str', off = 'Regex' },
  }
end

function M.build_title(base, state, defs)
  local parts = {}

  for _, def in ipairs(defs) do
    local hint = Keys.display(def.key)
    local label = state[def.field] and def.on or def.off
    parts[#parts + 1] = label .. ' ' .. hint
  end

  return base .. '  ' .. table.concat(parts, '  ')
end

function M.compile_rg_input(input)
  local comma_sources, split_error = Glob.split(input)
  if not comma_sources then return nil, split_error end
  if #comma_sources > 1 or not input:find('%s') then
    return Glob.compile_rg_list(input)
  end

  local ok, sources = pcall(vim.fn.shellsplit, input)
  if not ok then return nil, tostring(sources) end

  local compiled = {}
  for _, source in ipairs(sources) do
    local patterns, compile_error = Glob.compile_rg(source)
    if not patterns then return nil, compile_error end
    vim.list_extend(compiled, patterns)
  end
  return compiled, nil
end

function M.build_rg_args(state, base_additional_args, opts)
  local args = {}
  if type(base_additional_args) == 'function' then
    vim.list_extend(args, base_additional_args(opts) or {})
  elseif type(base_additional_args) == 'table' then
    vim.list_extend(args, base_additional_args)
  end

  if state.hidden then args[#args + 1] = '--hidden' end
  if state.no_ignore then args[#args + 1] = '--no-ignore' end
  if state.fixed_strings then args[#args + 1] = '--fixed-strings' end

  local globs = assert(M.compile_rg_input(state.glob_input))
  if #globs > 0 and not state.glob_input:match('%u') then
    args[#args + 1] = '--glob-case-insensitive'
  end

  for _, glob in ipairs(globs) do
    args[#args + 1] = '--glob'
    args[#args + 1] = glob
  end
  return args
end

function M.attach_toggle_mappings(prompt_bufnr, map, state, defs, title, create_finder)
  local action_state = require('telescope.actions.state')
  local function refresh()
    local picker = action_state.get_current_picker(prompt_bufnr)
    pcall(function() picker.prompt_border:change_title(title()) end)
    picker:refresh(create_finder(), { reset_prompt = false })
  end

  for _, def in ipairs(defs) do
    map('i', def.key, function()
      state[def.field] = not state[def.field]
      refresh()
    end)
  end

  return refresh
end

function M.attach_glob_input(map, state, cwd, refresh)
  completion_id = completion_id + 1
  local callback_name = '__vv_telescope_glob_complete_' .. completion_id
  _G[callback_name] = function(arglead, cmdline, cursor_pos)
    local input = cmdline or arglead or ''
    local cursor = math.max(0, math.min(cursor_pos or #input, #input))
    local result = PathCompletion.glob(input, { cwd = cwd or vim.fn.getcwd(), cursor = cursor })
    local before = input:sub(1, result.start_col)
    local after = input:sub(cursor + 1)
    return vim.tbl_map(function(item) return before .. item.word .. after end, result.items)
  end

  map('i', '<M-p>', function()
    local function cleanup()
      _G[callback_name] = nil
    end

    local ok, input_error = pcall(vim.ui.input, {
      prompt = 'Glob: ',
      default = state.glob_input,
      completion = 'customlist,v:lua.' .. callback_name,
    }, function(input)
      cleanup()
      if input == nil then return end
      local _, glob_error = M.compile_rg_input(input)
      if glob_error then
        vim.notify('Telescope glob: ' .. glob_error, vim.log.levels.ERROR)
        return
      end
      state.glob_input = vim.trim(input)
      refresh()
    end)
    if not ok then
      cleanup()
      error(input_error)
    end
  end)
end

return M
