-- nvim-treesitter：FileType 触发 + 按需异步安装 parser
-- parser 已装就直接启动高亮；缺失则（仅白名单内的 filetype）检查编译依赖后异步 install
-- 缺 tree-sitter CLI 等依赖时只提示安装方式，不替用户安装（见 deps.lua）
-- 手动安装
-- :TSInstall json lua python
-- 准入白名单：仅当「文件自身 filetype」命中此表，才允许触发自动安装；已装的 parser 不受限
-- 注意：它是闸门而非「确保已装」，注入语言（如 markdown 里的 ```sql）不经此表
local auto_install_allowlist = {
  'javascript', 'typescript', 'tsx',
  'markdown',
  'toml', 'xml', 'yaml', 'json',
  'lua', 'python',
  'go', 'rust',
  'bash', 'css',
}

-- 注入语言依赖：装宿主 parser 时一并装上，否则被注入的片段整块落回宿主的 @comment/@string
-- lua 的 ---@class / ---@param 走 luadoc（等价于 ts 的 jsdoc）
-- luap 是 string.match 等的 lua pattern，printf 是 string.format 的占位符
local injection_deps = {
  typescript = { 'jsdoc' },
  javascript = { 'jsdoc' },
  tsx        = { 'jsdoc' },
  lua        = { 'luadoc', 'luap', 'printf' },
}

local max_file_size = 100 * 1024 -- 超过此大小跳过高亮/缩进（防卡顿）

-- 会话内的 parser 状态，避免多个 buffer 同时触发时重复安装 / 重复提示
-- installing：正在安装；skipped：缺依赖或安装失败，本会话不再尝试
---@type table<string, 'installing'|'skipped'>
local state = {}

local function notify(msg, level)
  vim.notify('[treesitter] ' .. msg, level or vim.log.levels.INFO)
end

-- 能否对该 buffer 启动 treesitter（FileType 回调与安装完成后的补启动共用）
local function should_attach(buf)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then return false end

  local ft = vim.bo[buf].filetype
  if ft == '' or ft == 'yazi' or vim.bo[buf].buftype ~= '' then return false end

  local st = vim.uv.fs_stat(vim.api.nvim_buf_get_name(buf))
  return not (st and st.size > max_file_size)
end

-- 'broken' 表示 .so 存在但加载失败（ABI 不匹配 / 文件损坏），重装需要 force
---@return 'ok'|'missing'|'broken'
local function parser_state(name)
  local ok, added = pcall(vim.treesitter.language.add, name)
  if not ok then return 'broken' end
  return added and 'ok' or 'missing'
end

-- 仅当该语言带 indents query 时才启用 nvim-treesitter 缩进
-- 否则 get_indent 对每一行返回 -1（不动），并把 autoindent 等内置缩进全顶掉
-- markdown 例外：自身无可用缩进规则，但围栏代码块里的注入语言有，交给 markdown-indent.lua 按注入树分发
local function set_ts_indent(buf, lang)
  if lang == 'markdown' then
    vim.bo[buf].indentexpr = "v:lua.require'plugins.specs.code.treesitter.markdown-indent'.get_indent(v:lnum)"
    return
  end

  local ok, query = pcall(vim.treesitter.query.get, lang, 'indents')
  if ok and query then
    vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter.indent'.get_indent(v:lnum)"
  end
end

-- 启动高亮并按需挂缩进，成功返回 true
local function start_treesitter(buf, lang)
  if not pcall(vim.treesitter.start, buf, lang) then return false end
  set_ts_indent(buf, lang)
  return true
end

-- parser 异步装完后，把所有匹配该语言、尚未启动的缓冲区补上高亮
local function start_pending_buffers(lang)
  local started = 0
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if should_attach(b) and not vim.treesitter.highlighter.active[b] then
      local blang = vim.treesitter.language.get_lang(vim.bo[b].filetype) or vim.bo[b].filetype
      if blang == lang and start_treesitter(b, lang) then
        started = started + 1
      end
    end
  end
  return started
end

-- 先确认编译依赖，缺失只提示用户自行安装（不替用户装），并在本会话内不再重试
local function install_parsers(lang, names, force)
  local label = table.concat(names, ', ')

  local missing = require('plugins.specs.code.treesitter.deps').missing_message()
  if missing then
    for _, name in ipairs(names) do state[name] = 'skipped' end
    notify('Cannot install ' .. label .. ' parser.\n' .. missing, vim.log.levels.WARN)
    return
  end

  for _, name in ipairs(names) do state[name] = 'installing' end
  notify('Installing ' .. label .. ' parser (async, non-blocking)...')

  -- install 失败不会抛错，回调收到 err=nil 且 ok=false，两者都要判断
  require('nvim-treesitter').install(names, { force = force }):await(vim.schedule_wrap(function(err, ok)
    if err or not ok then
      for _, name in ipairs(names) do state[name] = 'skipped' end
      notify(
        'Failed to install ' .. label .. (err and (': ' .. tostring(err)) or '') .. '\nDetails: :TSLog / :checkhealth nvim-treesitter',
        vim.log.levels.ERROR
      )
      return
    end

    for _, name in ipairs(names) do state[name] = nil end

    local started = start_pending_buffers(lang)
    notify(started > 0
      and (label .. ' ready, highlighting enabled (' .. started .. ' buffer' .. (started > 1 and 's' or '') .. ')')
      or (label .. ' ready, run :e to reload the current buffer'))
  end))
end

-- treesitter-context 的高亮：跟随 CursorLine/LineNr，换主题后需重算
local function apply_context_hl()
  local ctx_bg  = vim.api.nvim_get_hl(0, { name = 'CursorLine', link = false }).bg
  local line_nr = vim.api.nvim_get_hl(0, { name = 'LineNr', link = false })
  vim.api.nvim_set_hl(0, 'TreesitterContext',                 { bg = ctx_bg })
  vim.api.nvim_set_hl(0, 'TreesitterContextLineNumber',       { bg = ctx_bg, fg = line_nr.fg })
  vim.api.nvim_set_hl(0, 'TreesitterContextBottom',           { bg = ctx_bg })
  vim.api.nvim_set_hl(0, 'TreesitterContextLineNumberBottom', { bg = ctx_bg, fg = line_nr.fg })
end

---@type PackSpec
return {
  desc = '语法高亮与语法树',
  url = 'https://github.com/nvim-treesitter/nvim-treesitter',
  main = 'nvim-treesitter',
  dependencies = { 'https://github.com/nvim-treesitter/nvim-treesitter-context' },
  build = ':TSUpdate',
  loadInVSCode = true,

  config = function()
    require('treesitter-context').setup({
      enable = true, max_lines = 3, min_window_height = 0,
      line_numbers = true, multiline_threshold = 20,
      trim_scope = 'outer', mode = 'cursor', separator = nil, zindex = 20,
    })

    apply_context_hl()
    vim.api.nvim_create_autocmd('ColorScheme', {
      group = vim.api.nvim_create_augroup('NativeTreesitterContextHl', { clear = true }),
      callback = apply_context_hl,
    })

    vim.api.nvim_create_autocmd('FileType', {
      group = vim.api.nvim_create_augroup('NativeTreesitter2', { clear = true }),
      callback = function(args)
        local buf = args.buf
        if not should_attach(buf) then return end

        local ft = vim.bo[buf].filetype
        local lang = vim.treesitter.language.get_lang(ft) or ft

        -- parser 已就绪：直接启动，不受白名单限制
        if parser_state(lang) == 'ok' then
          start_treesitter(buf, lang)
        end

        if not vim.list_contains(auto_install_allowlist, lang) then return end

        -- 收集还没装的 parser（含 jsdoc 等注入依赖）；正在装或已跳过的不重复处理
        local targets = { lang }
        vim.list_extend(targets, injection_deps[lang] or {})

        local to_install, broken = {}, false
        for _, name in ipairs(targets) do
          if not state[name] then
            local s = parser_state(name)
            if s ~= 'ok' then
              table.insert(to_install, name)
              broken = broken or s == 'broken'
            end
          end
        end

        if #to_install > 0 then
          install_parsers(lang, to_install, broken)
        end
      end,
    })
  end,
}
