-- nvim-treesitter：FileType 触发 + 按需异步安装 parser
-- 不能用声明式 ft/events：需要在 FileType 回调里判断 parser 是否已装、未装则异步 install
-- 装完再回调启动高亮。所以用 lazy='manual' 自管生命周期
-- 手动安装
-- :TSInstall json lua python
-- 准入白名单：仅当「文件自身 filetype」命中此表，才允许触发自动安装
-- 注意：它是闸门而非「确保已装」，注入语言（如 markdown 里的 ```sql）不经此表
local auto_install_allowlist = {
  'javascript', 'typescript', 'tsx', 'jsdoc',
  'markdown', 'markdown_inline',
  'toml', 'xml', 'yaml', 'json',
  'lua', 'python',
  'go', 'rust',
  'bash', 'css',
}

local injection_deps = {
  typescript = { 'jsdoc' },
  javascript = { 'jsdoc' },
  tsx        = { 'jsdoc' },
}

local max_file_size = 100 * 1024 -- 超过此大小跳过高亮/缩进（防卡顿）

-- 仅当该语言带 indents query 时才启用 nvim-treesitter 缩进
-- 否则 get_indent 会对每一行返回 -1（不动），并把 autoindent/GetLuaIndent 等内置缩进全顶掉
-- 典型如 lua：缺 indents.scm，交还内置 GetLuaIndent() 反而正确（函数体 +2）
local function set_ts_indent(buf, lang)
  if vim.treesitter.query.get(lang, 'indents') then
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
    if vim.api.nvim_buf_is_loaded(b) then
      local blang = vim.treesitter.language.get_lang(vim.bo[b].filetype) or vim.bo[b].filetype
      if blang == lang and start_treesitter(b, lang) then
        started = started + 1
      end
    end
  end
  return started
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

-- treesitter-context 是全局配置：首个缓冲区就绪时加载并 setup 一次
-- 守卫放在模块作用域：lazy='manual' 的加载器会在 ctx.load() 时重跑 config 拿到新闭包，
-- 闭包级守卫会失效；模块文件只求值一次，这里才能保证全局只 setup 一次
local context_ready = false
local function setup_context_once(ctx)
  if context_ready then return end
  context_ready = true

  ctx.load() -- 此时才真正 packadd treesitter-context
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
end

---@type PackSpec
return {
  desc = '语法高亮与语法树',
  url = 'https://github.com/nvim-treesitter/nvim-treesitter',
  main = 'nvim-treesitter',
  dependencies ={ 'https://github.com/nvim-treesitter/nvim-treesitter-context' },
  build =':TSUpdate',
  loadInVSCode = true,
  lazy = 'manual',

  config = function(_, ctx)
    vim.api.nvim_create_autocmd('FileType', {
      group = vim.api.nvim_create_augroup('NativeTreesitter2', { clear = true }),
      callback = function(args)
        local buf = args.buf
        local ft = vim.bo[buf].filetype
        if ft == '' or ft == 'yazi' or vim.bo[buf].buftype ~= '' then return end

        local ok, st = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(buf))
        if ok and st and st.size > max_file_size then return end

        local lang = vim.treesitter.language.get_lang(ft) or ft
        if not vim.tbl_contains(auto_install_allowlist, lang) then return end

        -- 收集还没装的 parser（含 jsdoc 等注入依赖）
        local targets = { lang }
        for _, dep in ipairs(injection_deps[lang] or {}) do table.insert(targets, dep) end

        local to_install = {}
        for _, name in ipairs(targets) do
          local no_err, added = pcall(vim.treesitter.language.add, name)
          if not no_err or not added then table.insert(to_install, name) end
        end

        if #to_install > 0 then
          ctx.load() -- 需要下载 parser：此时才真正 packadd 加载插件
          local names = table.concat(to_install, ', ')
          vim.notify('🌱 Installing ' .. names .. ' parser (async, non-blocking)...', vim.log.levels.INFO)

          local ts = require('nvim-treesitter')
          if not ts.install then
            vim.cmd('TSInstall ' .. table.concat(to_install, ' '))
            return
          end

          -- force=true 绕过 nvim-treesitter 的短路逻辑（get_installed 误判 runtime/queries）
          ts.install(to_install, { force = true }):await(function(err)
            if err then
              vim.notify('❌ Failed to install ' .. names .. ': ' .. tostring(err), vim.log.levels.ERROR)
              return
            end
            local started = start_pending_buffers(lang)
            if started > 0 then setup_context_once(ctx) end

            local msg = started > 0
              and ('✅ ' .. names .. ' ready, highlighting enabled (' .. started .. ' buffer' .. (started > 1 and 's' or '') .. ')')
              or ('✅ ' .. names .. ' ready, run :e to reload the current buffer')
            vim.notify(msg, vim.log.levels.INFO)
          end)
          return
        end

        -- parser 已就绪：直接启动
        if start_treesitter(buf, lang) then
          setup_context_once(ctx)
        end
      end,
    })
  end,
}
