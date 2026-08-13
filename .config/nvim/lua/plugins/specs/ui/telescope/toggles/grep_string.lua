local Shared = require('plugins.specs.ui.telescope.toggles.shared')
local Keys = require('vv-utils.keys')

local M = {}

function M.open(base_opts)
  local opts = vim.tbl_extend('force', {}, base_opts or {})
  local search = tostring(opts.search or vim.fn.expand('<cword>'))
  local state = { hidden = false, no_ignore = false, fixed_strings = true, glob_input = '' }
  local defs = Shared.grep_defs()
  local function title()
    local suffix = state.glob_input ~= '' and state.glob_input or 'glob'
    return Shared.build_title('Find Word (' .. search:gsub('\n', '\\n') .. ')', state, defs)
      .. '  ' .. suffix .. ' ' .. Keys.display('<M-p>')
  end
  local function create_finder()
    local args = vim.deepcopy(require('telescope.config').values.vimgrep_arguments)
    vim.list_extend(args, Shared.build_rg_args(state, opts.additional_args, opts))
    vim.list_extend(args, { '--', search })
    if opts.grep_open_files then
      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buftype == '' then
          local path = vim.api.nvim_buf_get_name(bufnr)
          if path ~= '' then args[#args + 1] = path end
        end
      end
    elseif opts.search_dirs then
      for _, path in ipairs(opts.search_dirs) do
        args[#args + 1] = vim.fs.normalize(vim.fn.expand(path))
      end
    end
    return require('telescope.finders').new_oneshot_job(args, {
      entry_maker = require('telescope.make_entry').gen_from_vimgrep(opts),
      cwd = opts.cwd,
    })
  end

  require('telescope.pickers').new(opts, {
    prompt_title = title(),
    finder = create_finder(),
    previewer = require('telescope.config').values.grep_previewer(opts),
    sorter = require('telescope.config').values.generic_sorter(opts),
    push_cursor_on_edit = true,
    attach_mappings = function(prompt_bufnr, map)
      local refresh = Shared.attach_toggle_mappings(prompt_bufnr, map, state, defs, title, create_finder)
      Shared.attach_glob_input(map, state, opts.cwd, refresh)
      return true
    end,
  }):find()
end

return M
