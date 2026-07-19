-- 符号导航：gO 全局符号、go 文档符号（无 LSP 时降级到 treesitter）
--
-- 这里注册的是「全局」映射；LSP attach 后的 buffer 级覆盖见 keymaps.lua，
-- 后者会复用本模块导出的 open_workspace_symbols

local M = {}

-- gO 全局符号（telescope 动态 workspace symbols）
-- 默认「显示全部」，Alt-h 切到「隐藏变量/常量」干净模式：
--   workspace/symbol 是扁平结果，区分不了「局部 vs 顶层」变量（实测顶层 const MOTION_INITIAL
--   与函数内 useState 的 isFocused，kind 都是 Variable、containerName 都为空）。所以只能整类
--   隐藏 variable/constant —— 默认不隐藏，免得连 MOTION_INITIAL 这种顶层常量都搜不到
-- 实现：自定义 entry_maker 读 ws_hide_vars 标志，命中就返回 nil 丢弃；切换时只 picker:refresh
--   原地重跑当前 finder（不 close/重开），无闪烁、保留当前输入。状态跨 buffer 持久
local ws_hide_vars = false

local function ws_title()
  return ws_hide_vars and '全局符号 · 已隐藏变量 (M-h 显示)' or '全局符号 (M-h 隐藏变量/常量)'
end

function M.open_workspace_symbols()
  local opts = { prompt_title = ws_title() } -- 标题随当前状态（开关跨 buffer 持久）
  local base_maker = require('telescope.make_entry').gen_from_lsp_symbols(opts)
  opts.entry_maker = function(item)
    if ws_hide_vars then
      local k = tostring(item.kind):lower()
      if k == 'variable' or k == 'constant' then return nil end
    end
    return base_maker(item)
  end
  opts.attach_mappings = function(_, map)
    map({ 'i', 'n' }, '<M-h>', function(prompt_bufnr)
      local picker = require('telescope.actions.state').get_current_picker(prompt_bufnr)
      ws_hide_vars = not ws_hide_vars
      picker:refresh(nil, { reset_prompt = false }) -- 原地重跑 finder，按新状态过滤
      -- 实时更新标题（API 随版本异，pcall 兜底）；notify 保证一定有反馈
      pcall(function() picker.layout.prompt.border:change_title(ws_title()) end)
      vim.notify((ws_hide_vars and ' 隐藏' or ' 显示') .. '变量/常量', vim.log.levels.INFO)
    end)
    return true -- 保留 telescope 默认映射（合并而非覆盖）
  end
  require('telescope.builtin').lsp_dynamic_workspace_symbols(opts)
end

-- go 文档符号：LSP 优先（Trouble 面板），无 LSP 时降级到 telescope treesitter 符号
-- 适合 markdown/man/conf 等没有 LSP 的 filetype
local function open_document_symbols()
  local buf = vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients({ bufnr = buf, method = 'textDocument/documentSymbol' })

  if #clients > 0 then
    local trouble = require('trouble')
    if trouble.is_open('doc_symbols') then
      return trouble.close('doc_symbols')
    end

    -- 符号树和 vv-explorer 都在左侧，避免同时占用：开符号树前先关文件树
    -- 只在 vv-explorer 已加载时检查（不强行 require 一个没用过的插件）
    pcall(function()
      local explorer = package.loaded['vv-explorer']
      if explorer and explorer.is_open() then explorer.close() end
    end)

    local view = trouble.open({ mode = 'doc_symbols', focus = true })
    if not view then return end

    -- 数据就绪后设 foldlevel，触发 trouble 的 OptionSet 钩子 → fold_level（会重渲染）
    -- 代码：filter 已剔除 import / 函数内局部变量噪音（见 trouble.lua），剩下的是「干净结构大纲」，
    --       故 foldlevel=99 全展开，一眼看到所有函数；噪音用 H 键按需显示
    -- markdown：标题按层级嵌套，foldlevel=4 展示一~四级标题，仅折叠四级以下（H5+）
    local fold_level = vim.bo[buf].filetype == 'markdown' and 4 or 99

    view:wait(function()
      local win = view.win and view.win.win
      if win and vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_call(win, function() vim.cmd('setlocal foldlevel=' .. fold_level) end)
      end
    end)
  else
    -- 无 LSP：尝试 telescope treesitter（依赖 locals.scm，仅代码类语言有）
    local lang = vim.treesitter.language.get_lang(vim.bo[buf].filetype)
      or vim.bo[buf].filetype
    local ok_q, query = pcall(vim.treesitter.query.get, lang, 'locals')
    local locals_ok = ok_q and query ~= nil

    if locals_ok then
      require('telescope.builtin').treesitter()
      return
    end

    -- 无 locals 查询：用 treesitter 自身解析结构符号
    local ts_ok, parser = pcall(vim.treesitter.get_parser, buf, lang)
    if ts_ok then
      local tstree = parser:parse()[1]
      if tstree then
        local ok_q2, heading_q = pcall(vim.treesitter.query.parse, lang, [[
          (atx_heading) @heading
          (setext_heading) @heading
        ]])
        if ok_q2 then
          local items = {}
          for _, node, _ in heading_q:iter_captures(tstree:root(), buf, 0, -1) do
            local text = vim.treesitter.get_node_text(node, buf)
            local start_line = node:start()
            local level = nil
            for child in node:iter_children() do
              local t = child:type()
              local n = t:match('^atx_h(%d)_marker$')
              if n then level = tonumber(n); break end
            end
            if not level then
              for child in node:iter_children() do
                local t = child:type()
                if t:match('underline') then level = t:match('h(%d)') and tonumber(t:match('h(%d)')) or 1; break end
              end
            end
            if text and text ~= '' then
              table.insert(items, {
                lnum = start_line + 1,
                text = text,
                level = level or 1,
              })
            end
          end
          if #items > 0 then
            local actions = require('telescope.actions')
            local action_state = require('telescope.actions.state')
            local conf = require('telescope.config').values
            require('telescope.pickers').new({}, {
              prompt_title = lang .. ' 符号',
              finder = require('telescope.finders').new_table {
                results = items,
                entry_maker = function(item)
                  return {
                    value = item,
                    display = string.rep('  ', item.level - 1) .. '# ' .. item.text,
                    ordinal = item.text:lower(),
                    filename = vim.api.nvim_buf_get_name(buf),
                    lnum = item.lnum,
                  }
                end,
              },
              previewer = conf.grep_previewer({}),
              sorter = conf.generic_sorter({}),
              attach_mappings = function(prompt_bufnr, _)
                actions.select_default:replace(function()
                  local sel = action_state.get_selected_entry()
                  actions.close(prompt_bufnr)
                  if sel then vim.api.nvim_win_set_cursor(0, { sel.lnum, 0 }) end
                end)
                return true
              end,
            }):find()
            return
          end
        end
      end
    end
    vim.notify('无可用 LSP 且 treesitter 无可用符号', vim.log.levels.WARN)
  end
end

function M.setup()
  local icons = require('vv-icons')

  -- gO 全局可用：nvim 在 LspAttach 会设 buffer-local gO（默认 document_symbol），会盖住全局映射，
  -- 故 LSP buffer 仍靠 keymaps.lua 里的 buffer-local gO 生效；这里补一个全局 gO 填补「无 LSP /
  -- 未 attach」的 buffer（help/man 等自带 buffer-local gO=TOC 的不受影响，会自动优先）
  -- 能否搜到符号取决于当前 buffer 有没有支持 workspace/symbol 的 LSP（没有则 telescope 提示）
  vim.keymap.set('n', 'gO', M.open_workspace_symbols, { desc = icons.vscode .. ' Workspace symbols' })

  vim.keymap.set('n', 'go', open_document_symbols, { desc = icons.vscode .. ' Document symbols' })
end

return M
