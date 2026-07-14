local M = {}

--- @class ToggleDef
--- @field key string 触发快捷键，如 `'<M-h>'`
--- @field field string 对应 state 表中的字段名
--- @field on string 激活时显示的标签
--- @field off string 未激活时显示的标签

--- 构建 picker 标题，格式：`base │ M-h:hidden  M-i:gitignore`
--- @param base string 标题前缀
--- @param state table<string, boolean> 当前各 toggle 的开关状态
--- @param defs ToggleDef[]
--- @return string
local function build_title(base, state, defs)
  local parts = {}

  for _, d in ipairs(defs) do
    local hint = d.key:gsub('[<>]', '')
    local label = state[d.field] and d.on or d.off
    parts[#parts + 1] = hint .. ':' .. label
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
  local state = { hidden = false, no_ignore = false, fixed_strings = false, globs = {} }

  local defs = {
    { key = '<M-h>', field = 'hidden',        on = 'hidden',    off = 'no-hidden' },
    { key = '<M-i>', field = 'no_ignore',     on = 'no-ignore', off = 'gitignore' },
    { key = '<M-f>', field = 'fixed_strings', on = 'Fixed-str', off = 'Regex'     },
  }

  local function build_grep_title()
    local title = build_title('Live Grep', state, defs)
    if #state.globs > 0 then
      title = title .. '  M-p:' .. table.concat(state.globs, ' ')
    else
      title = title .. '  M-p:glob'
    end
    return title
  end

  local function build_extra_args()
    local args = {}
    if state.hidden then args[#args + 1] = '--hidden' end
    if state.no_ignore then args[#args + 1] = '--no-ignore' end
    if state.fixed_strings then args[#args + 1] = '--fixed-strings' end

    -- glob 智能大小写：全小写 → 不敏感；任一含大写 → 精确（仿 rg --smart-case）
    if #state.globs > 0 then
      local has_upper = false
      for _, g in ipairs(state.globs) do
        if g:match('%u') then
          has_upper = true
          break
        end
      end
      if not has_upper then args[#args + 1] = '--glob-case-insensitive' end
    end

    for _, g in ipairs(state.globs) do
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

      -- <M-p>：输入 glob 模式（空格分隔，! 前缀排除），自动智能补全
      map('i', '<M-p>', function()
        local function norm(pattern)
          local negate = pattern:sub(1, 1) == '!'
          local body = negate and pattern:sub(2) or pattern

          -- 自动补 **/，让路径片段从 cwd 下任意深度匹配
          if not (body:sub(1, 3) == '**/' or body:sub(1, 1) == '/') then
            body = '**/' .. body
          end

          -- 末尾没通配符、且末段不像文件名（不含 .）→ 当目录名 → 补 /** 搜内部
          local no_prefix = body:gsub('^%*%*%/', '')
          local last_seg = no_prefix:match('[^/]*$') or ''
          if not no_prefix:match('[*?]') and not last_seg:match('%.') then
            body = body:match('/$') and (body .. '**') or (body .. '/**')
          end

          return (negate and '!' or '') .. body
        end

        -- 回显时把每条 glob 还原成用户当初敲的简洁形式（逐条去掉 **/ 前缀和 /** 后缀）
        local function denorm(glob)
          return (glob:gsub('^(!?)%*%*/', '%1'):gsub('/%*%*$', ''))
        end

        local display = {}
        for _, g in ipairs(state.globs) do
          display[#display + 1] = denorm(g)
        end

        vim.ui.input(
          {
            prompt = 'Glob 模式（空格分隔，! 前缀排除）: ',
            default = table.concat(display, ' '),
          },
          function(input)
            if input == nil then return end
            state.globs = {}
            for pattern in input:gmatch('%S+') do
              state.globs[#state.globs + 1] = norm(pattern)
            end
            refresh_picker()
          end
        )
      end)

      return true
    end,
  }))
end

return M
