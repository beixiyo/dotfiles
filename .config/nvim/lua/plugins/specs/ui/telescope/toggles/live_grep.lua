local Shared = require('plugins.specs.ui.telescope.toggles.shared')
local Keys = require('vv-utils.keys')

local M = {}

function M.open(base_opts)
  local opts = vim.tbl_extend('force', {}, base_opts or {})
  local base_additional_args = opts.additional_args
  local initial_fixed_strings = opts.initial_fixed_strings
  opts.initial_fixed_strings = nil
  local state = { hidden = false, no_ignore = false, fixed_strings = initial_fixed_strings ~= false, glob_input = '' }
  local defs = Shared.grep_defs()
  local function title()
    local suffix = state.glob_input ~= '' and state.glob_input or 'glob'
    return Shared.build_title('Live Grep', state, defs) .. '  ' .. suffix .. ' ' .. Keys.display('<M-p>')
  end
  local function create_finder()
    local args = vim.deepcopy(require('telescope.config').values.vimgrep_arguments)
    vim.list_extend(args, Shared.build_rg_args(state, base_additional_args, opts))
    return require('telescope.finders').new_async_job({
      command_generator = function(prompt)
        if not prompt or prompt == '' then return nil end
        return vim.list_extend(vim.deepcopy(args), { '--', prompt })
      end,
      entry_maker = require('telescope.make_entry').gen_from_vimgrep(opts),
      cwd = opts.cwd,
    })
  end

  require('telescope.builtin').live_grep(vim.tbl_extend('force', opts, {
    prompt_title = title(),
    additional_args = function() return Shared.build_rg_args(state, base_additional_args, opts) end,
    attach_mappings = function(prompt_bufnr, map)
      local refresh = Shared.attach_toggle_mappings(prompt_bufnr, map, state, defs, title, create_finder)
      Shared.attach_glob_input(map, state, opts.cwd, refresh)
      return true
    end,
  }))
end

return M
