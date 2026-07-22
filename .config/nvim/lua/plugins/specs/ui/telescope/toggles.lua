local Glob = require('vv-utils.glob')
local PathCompletion = require('vv-utils.path_completion')

local M = {}

local completion_id = 0

---@param input_opts table
---@param cwd string?
---@param on_confirm fun(input: string?)
local function input_glob(input_opts, cwd, on_confirm)
  completion_id = completion_id + 1
  local callback_name = '__vv_telescope_glob_complete_' .. completion_id

  _G[callback_name] = function(arglead, cmdline, cursor_pos)
    local input = cmdline or arglead or ''
    local cursor = math.max(0, math.min(cursor_pos or #input, #input))
    local result = PathCompletion.glob(input, {
      cwd = cwd or vim.fn.getcwd(),
      cursor = cursor,
    })
    local before = input:sub(1, result.start_col)
    local after = input:sub(cursor + 1)
    local items = {}
    for _, item in ipairs(result.items) do
      -- input() 的 customlist 只接受 string[]，且候选会替换整段输入
      items[#items + 1] = before .. item.word .. after
    end
    return items
  end

  local function cleanup()
    _G[callback_name] = nil
  end

  input_opts.completion = 'customlist,v:lua.' .. callback_name
  local ok, input_error = pcall(vim.ui.input, input_opts, function(input)
    cleanup()
    on_confirm(input)
  end)
  if not ok then
    cleanup()
    error(input_error)
  end
end

--- @class ToggleDef
--- @field key string 触发快捷键，如 `'<M-h>'`
--- @field field string 对应 state 表中的字段名
--- @field on string 激活时显示的标签
--- @field off string 未激活时显示的标签

--- 构建 picker 标题，格式：`base  hidden ⌥H  gitignore ⌥I`
--- @param base string 标题前缀
--- @param state table<string, boolean> 当前各 toggle 的开关状态
--- @param defs ToggleDef[]
--- @return string
local function build_title(base, state, defs)
  local parts = {}

  for _, d in ipairs(defs) do
    local hint = d.key
      :gsub('[<>]', '')
      :gsub('^C%-', '^')
      :gsub('^M%-', '⌥')
      :gsub('^S%-', '⇧')
      :gsub('(%a)$', string.upper)
    local label = state[d.field] and d.on or d.off
    parts[#parts + 1] = label .. ' ' .. hint
  end

  return base .. '  ' .. table.concat(parts, '  ')
end

--- 生成 attach_mappings 回调，按快捷键时原地 refresh finder
--- @param state table<string, boolean>
--- @param defs ToggleDef[]
--- @param title_base string 标题前缀，刷新时重新拼接
--- @param create_finder fun(): any 构造新 finder 的工厂函数
--- @return fun(prompt_bufnr: integer, map: fun): boolean
local function make_toggle_mappings(state, defs, title_base, create_finder)
  return function(prompt_bufnr, map)
    local action_state = require('telescope.actions.state')

    for _, d in ipairs(defs) do
      map('i', d.key, function()
        state[d.field] = not state[d.field]
        local picker = action_state.get_current_picker(prompt_bufnr)

        pcall(function()
          picker.prompt_border:change_title(build_title(title_base, state, defs))
        end)

        picker:refresh(create_finder(), { reset_prompt = false })
      end)
    end

    return true
  end
end

--- 带 toggle 的 find_files，支持切换 hidden / no-ignore
--- @param base_opts? table telescope.builtin.find_files 的选项
function M.find_files(base_opts)
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

  -- 允许使用绝对路径
  local cwd = opts.cwd or vim.uv.cwd()
  local cwd_slash = cwd:sub(-1) == '/' and cwd or (cwd .. '/')

  local function make_entry_with_abs(o)
    local base = require('telescope.make_entry').gen_from_file(o)
    return function(line)
      local entry = base(line)
      if entry then
        entry.ordinal = cwd_slash .. entry.ordinal
      end
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
    prompt_title = build_title('Find Files', state, defs),
    entry_maker = make_entry_with_abs(opts),
    attach_mappings = make_toggle_mappings(state, defs, 'Find Files', create_finder),
  }))
end

--- 带 toggle 的 live_grep，支持切换 hidden / no-ignore / fixed-strings，以及 glob 范围过滤
--- @param base_opts? table telescope.builtin.live_grep 的选项
function M.live_grep(base_opts)
  local opts = base_opts or {}
  local state = { hidden = false, no_ignore = false, fixed_strings = true, glob_input = '' }

  -- 新输入用 VS Code 风格顶层逗号分隔；无顶层逗号时保留旧的 shell-like 空格分隔
  -- 因此单条含空格路径可写为 "path with spaces/**"
  local function compile_rg_input(input)
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

  local defs = {
    { key = '<M-h>', field = 'hidden',        on = 'hidden',    off = 'no-hidden' },
    { key = '<M-i>', field = 'no_ignore',     on = 'no-ignore', off = 'gitignore' },
    { key = '<M-f>', field = 'fixed_strings', on = 'Fixed-str', off = 'Regex'     },
  }

  local function build_grep_title()
    local title = build_title('Live Grep', state, defs)
    if state.glob_input ~= '' then
      title = title .. '  ' .. state.glob_input .. ' ⌥P'
    else
      title = title .. '  glob ⌥P'
    end
    return title
  end

  local function build_extra_args()
    local args = {}
    if state.hidden then args[#args + 1] = '--hidden' end
    if state.no_ignore then args[#args + 1] = '--no-ignore' end
    if state.fixed_strings then args[#args + 1] = '--fixed-strings' end

    local globs = assert(compile_rg_input(state.glob_input))

    -- glob 智能大小写：全小写 → 不敏感；任一含大写 → 精确（仿 rg --smart-case）
    if #globs > 0 and not state.glob_input:match('%u') then
      args[#args + 1] = '--glob-case-insensitive'
    end

    for _, g in ipairs(globs) do
      args[#args + 1] = '--glob'
      args[#args + 1] = g
    end
    return args
  end

  local function create_finder()
    local conf = require('telescope.config').values
    local vimgrep_args = vim.deepcopy(conf.vimgrep_arguments)

    for _, arg in ipairs(build_extra_args()) do
      vimgrep_args[#vimgrep_args + 1] = arg
    end

    return require('telescope.finders').new_async_job({
      command_generator = function(prompt)
        if not prompt or prompt == '' then return nil end
        local cmd = vim.deepcopy(vimgrep_args)
        cmd[#cmd + 1] = '--'
        cmd[#cmd + 1] = prompt
        return cmd
      end,
      entry_maker = require('telescope.make_entry').gen_from_vimgrep(opts),
      cwd = opts.cwd,
    })
  end

  require('telescope.builtin').live_grep(vim.tbl_extend('force', opts, {
    prompt_title = build_grep_title(),
    additional_args = function() return build_extra_args() end,
    attach_mappings = function(prompt_bufnr, map)
      local action_state = require('telescope.actions.state')

      local function refresh_picker()
        local picker = action_state.get_current_picker(prompt_bufnr)
        pcall(function() picker.prompt_border:change_title(build_grep_title()) end)
        picker:refresh(create_finder(), { reset_prompt = false })
      end

      for _, d in ipairs(defs) do
        map('i', d.key, function()
          state[d.field] = not state[d.field]
          refresh_picker()
        end)
      end

      -- <M-p>：输入 VS Code 风格 glob（顶层逗号分隔，! 前缀排除）
      map('i', '<M-p>', function()
        input_glob(
          {
            prompt = 'Glob: ',
            default = state.glob_input,
          },
          opts.cwd,
          function(input)
            if input == nil then return end
            local _, glob_error = compile_rg_input(input)
            if glob_error then
              vim.notify('Telescope glob: ' .. glob_error, vim.log.levels.ERROR)
              return
            end
            state.glob_input = vim.trim(input)
            refresh_picker()
          end
        )
      end)

      return true
    end,
  }))
end

return M
