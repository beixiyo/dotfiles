-- 最近文件 picker：默认限制在当前 Git 项目，可在项目与全局范围间切换
local M = {}

local function collect_recent_files()
  local current_file = vim.api.nvim_buf_get_name(0)
  local results = {}
  local seen = {}

  local function add(file)
    if file == '' or seen[file] then return end

    local stat = vim.uv.fs_stat(file)
    if not stat or stat.type ~= 'file' then return end

    seen[file] = true
    results[#results + 1] = file
  end

  add(current_file)

  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buffer].buflisted then
      add(vim.api.nvim_buf_get_name(buffer))
    end
  end

  for _, file in ipairs(vim.v.oldfiles) do
    add(file)
  end

  return results
end

local function in_root(file, root)
  local prefix = root:sub(-1) == '/' and root or (root .. '/')
  return file:sub(1, #prefix) == prefix
end

local function title(project_scope)
  return ('Recent Files  %s ⌥P'):format(project_scope and 'project' or 'global')
end

function M.open()
  local root = require('vv-utils.git').root(vim.uv.cwd())
  local state = { project_scope = root ~= nil }
  local all_files = collect_recent_files()
  local finders = require('telescope.finders')
  local make_entry = require('telescope.make_entry')

  local function create_finder()
    local results = all_files

    if state.project_scope and root then
      results = vim.tbl_filter(function(file)
        return in_root(file, root)
      end, all_files)
    end

    return finders.new_table({
      results = results,
      entry_maker = make_entry.gen_from_file({}),
    })
  end

  local function attach_mappings(prompt_bufnr, map)
    if not root then return true end

    local function toggle_scope()
      state.project_scope = not state.project_scope

      local picker = require('telescope.actions.state').get_current_picker(prompt_bufnr)
      pcall(function()
        picker.prompt_border:change_title(title(state.project_scope))
      end)
      picker:refresh(create_finder(), { reset_prompt = false })
    end

    map({ 'i', 'n' }, '<M-p>', toggle_scope)

    return true
  end

  local conf = require('telescope.config').values

  require('telescope.pickers').new({}, {
    prompt_title = root and title(state.project_scope) or 'Recent Files  global',
    finder = create_finder(),
    previewer = conf.grep_previewer({}),
    sorter = conf.file_sorter({}),
    attach_mappings = attach_mappings,
  }):find()
end

return M
