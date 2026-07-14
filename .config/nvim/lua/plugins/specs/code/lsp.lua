-- LSP 与代码诊断
-- 架构（Neovim 0.11+ 原生范式）：
--   1. mason.nvim           —— 安装 LSP / formatter 二进制（:Mason 面板）
--   2. mason-lspconfig.nvim —— 桥接层：Mason 装了什么就自动 vim.lsp.enable() 什么
--   3. nvim-lspconfig       —— 提供 ~300 个 server 的默认配置
--   4. vim.lsp.enable()     —— 按需启停 client、自动 attach/detach
--
-- 工作流：:Mason 手动安装 server → mason-lspconfig 检测到 → 自动 enable
--         → 打开对应 filetype 文件时自动 attach（懒启动）
--
-- 不能 lazy 加载：mason-lspconfig.automatic_enable 内部 vim.lsp.enable() 注册 FileType
-- 是异步/延迟的，BufReadPre 触发时会错过当前 buffer 的 FileType（auto-session 恢复尤其明显）
---@type PackSpec
return {
  desc = 'LSP 与代码诊断',
  url = 'https://github.com/neovim/nvim-lspconfig',
  main = 'lspconfig',
  dependencies = {
    'https://github.com/mason-org/mason.nvim',
    'https://github.com/mason-org/mason-lspconfig.nvim',
    'beixiyo/vv-icons.nvim',
  },

  config = function()
    -- ── 修复 inotify watch 配额耗尽 ──────────────────────────────────────────
    -- ~ 本身是 dotfiles 仓库,在 ~ 下开文件时 LSP 工作区根会落到 $HOME。
    -- Neovim 的 LSP 文件监听(:h inotify-limitations)会对工作区根跑
    -- `inotifywait --recursive`,于是递归监听 ~/.npm ~/.cache ~/.cargo 等
    -- 十几万个目录,瞬间吃满 inotify watch 配额 → "inotify(7) limit reached"。
    -- 这里只掐掉「工作区根 == 家目录」这一病态情况,真实项目(~/code/*)有自己的
    -- 根,文件监听照常工作。
    do
      local wf = require('vim.lsp._watchfiles')
      local orig_watchfunc = wf._watchfunc
      local home = vim.fs.normalize(vim.uv.os_homedir())

      wf._watchfunc = function(base_dir, opts, callback)
        if vim.fs.normalize(base_dir) == home then
          return function() end
        end
        return orig_watchfunc(base_dir, opts, callback)
      end
    end

    local icons = require('vv-icons')
    local diag_icons = {
      Error = icons.diagnostics_error,
      Warn  = icons.diagnostics_warn,
      Hint  = icons.diagnostics_hint,
      Info  = icons.diagnostics_info,
    }

    require('mason').setup({})
    require('mason-lspconfig').setup({
      ensure_installed = { 'tsgo', 'dprint' },
      automatic_enable = {
        exclude = { 'ts_ls' },
      },
    })

    -- tsgo 设置：仅保留诊断/补全/导航偏好，格式化交由 dprint（~/.config/dprint/dprint.json）
    vim.lsp.config['tsgo'] = {
      settings = {
        typescript = {
          preferences = {
            importModuleSpecifier = 'relative',
          },
        },
        javascript = {
          preferences = {
            importModuleSpecifier = 'relative',
          },
        },
      },
    }

    -- 左侧诊断 Icon
    local s = vim.diagnostic.severity
    vim.diagnostic.config({
      virtual_text = {
        spacing = 2,
        source = 'if_many',
        prefix = function(diagnostic)
          if diagnostic.severity == s.ERROR then return diag_icons.Error
          elseif diagnostic.severity == s.WARN then return diag_icons.Warn
          elseif diagnostic.severity == s.HINT then return diag_icons.Hint
          else return diag_icons.Info end
        end,
      },
      signs = {
        text = {
          [s.ERROR] = diag_icons.Error,
          [s.WARN]  = diag_icons.Warn,
          [s.HINT]  = diag_icons.Hint,
          [s.INFO]  = diag_icons.Info,
        },
      },
      underline = true,
      update_in_insert = false,
      severity_sort = true,
      float = { border = 'rounded', source = 'if_many' },
    })

    -- 一次性安全应用当前文件全部可编辑修复，保留 buffer modified 状态
    local function apply_all_quickfix()
      local result = require('vv-utils.lsp.code_actions').fix_document({
        bufnr = vim.api.nvim_get_current_buf(),
        save = false,
      })
      if result.error then
        local level = result.error.code == 'no_quickfixes'
            and vim.log.levels.INFO
            or vim.log.levels.WARN
        return vim.notify(result.error.message, level)
      end
      vim.notify(('Applied %d fixes'):format(result.edits_count), vim.log.levels.INFO)
    end

    -- gO 全局符号（telescope 动态 workspace symbols）
    -- 默认「显示全部」，Alt-h 切到「隐藏变量/常量」干净模式：
    --   workspace/symbol 是扁平结果，区分不了「局部 vs 顶层」变量（实测顶层 const MOTION_INITIAL
    --   与函数内 useState 的 isFocused，kind 都是 Variable、containerName 都为空）。所以只能整类
    --   隐藏 variable/constant —— 默认不隐藏，免得连 MOTION_INITIAL 这种顶层常量都搜不到。
    -- 实现：自定义 entry_maker 读 ws_hide_vars 标志，命中就返回 nil 丢弃；切换时只 picker:refresh
    --   原地重跑当前 finder（不 close/重开），无闪烁、保留当前输入。状态跨 buffer 持久。
    local ws_hide_vars = false
    local function ws_title()
      return ws_hide_vars and '全局符号 · 已隐藏变量 (M-h 显示)' or '全局符号 (M-h 隐藏变量/常量)'
    end
    local function open_workspace_symbols()
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

    -- gO 全局可用：nvim 在 LspAttach 会设 buffer-local gO（默认 document_symbol），会盖住全局映射，
    -- 故 LSP buffer 仍靠下方 LspAttach 里的 buffer-local gO 生效；这里补一个全局 gO 填补「无 LSP /
    -- 未 attach」的 buffer（help/man 等自带 buffer-local gO=TOC 的不受影响，会自动优先）。
    -- 能否搜到符号取决于当前 buffer 有没有支持 workspace/symbol 的 LSP（没有则 telescope 提示）。
    vim.keymap.set('n', 'gO', open_workspace_symbols, { desc = icons.vscode .. ' Workspace symbols' })

    -- go 文档符号：LSP 优先（Trouble 面板），无 LSP 时降级到 telescope treesitter 符号
    -- 适合 markdown/man/conf 等没有 LSP 的 filetype
    vim.keymap.set('n', 'go', function()
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
    end, { desc = icons.vscode .. ' Document symbols' })

    -- ================================
    -- LSP 快捷键（buffer 级，仅在 LSP attach 后生效）
    --
    -- Neovim 0.11+ 已内建的默认映射：
    --   grn → rename            gra → code_action
    --   grr → references        gri → implementation
    --   go  → document_symbol   gO → workspace_symbol   <C-S>→ signature_help (insert)
    --   [d / ]d → 上/下一个诊断  <C-W>d → 诊断浮窗
    -- 0.12 新增：
    --   grt → type_definition    grx → codelens.run
    --
    -- 策略：gr* 前缀沿用官方，UI 用 Trouble 替代 qflist
    -- ================================
    vim.api.nvim_create_autocmd('LspAttach', {
      group = vim.api.nvim_create_augroup('UserLspConfig', {}),
      callback = function(event)
        local map = vim.keymap.set
        local client = vim.lsp.get_client_by_id(event.data.client_id)
        local bufopts = function(desc) return { desc = desc, buffer = event.buf } end

        -- 跳转类（open 而非 toggle：面板已打开时刷新内容，不关闭）
        local function open_trouble(mode)
          -- Trouble 和 vv-explorer 都在左侧，避免同时占用
          pcall(function()
            local explorer = package.loaded['vv-explorer']
            if explorer and explorer.is_open() then explorer.close() end
          end)
          require('trouble').open({ mode = mode, focus = true })
        end

        map('n', 'gd',  function() open_trouble('lsp_definitions') end,      bufopts(icons.jumps .. ' Definitions'))
        map('n', 'gD',  function() open_trouble('lsp_declarations') end,     bufopts(icons.jumps .. ' Declarations'))
        map('n', 'grr', function() open_trouble('lsp_references') end,       bufopts(icons.jumps .. ' References'))
        map('n', 'gri', function() open_trouble('lsp_implementations') end,  bufopts(icons.jumps .. ' Implementations'))
        map('n', 'grt', function() open_trouble('lsp_type_definitions') end, bufopts(icons.jumps .. ' Type definitions'))

        -- go 由全局降级映射管理（LSP→treesitter 降级，见全局键绑定），这里删掉 Neovim 默认
        pcall(vim.keymap.del, 'n', 'go', { buffer = event.buf })
        map('n', 'gO',  open_workspace_symbols,  bufopts(icons.vscode .. ' Workspace symbols'))

        -- K：悬停信息（覆盖默认，"再按一次关闭"切换行为）
        map('n', 'K', function()
          local ok_docs, docs = pcall(require, 'noice.lsp.docs')
          if ok_docs and docs._messages then
            local msg = docs._messages['hover']
            if msg and msg.win and msg:win() then docs.hide(msg); return end
          end
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            local ok, marker = pcall(vim.api.nvim_win_get_var, win, 'textDocument/hover')
            if ok and marker then
              pcall(vim.api.nvim_win_close, win, true)
              return
            end
          end
          vim.lsp.buf.hover({ silent = true })
        end, vim.tbl_extend('force', bufopts(icons.vscode .. ' Toggle hover'), { silent = true }))

        -- 操作类
        if client and client:supports_method('textDocument/rename', { bufnr = event.buf }) then
          map('n', 'grn', vim.lsp.buf.rename, bufopts(icons.rename .. ' Rename'))
        end
        if client and client:supports_method('textDocument/codeAction', { bufnr = event.buf }) then
          map({ 'n', 'x' }, 'gra', vim.lsp.buf.code_action, bufopts(icons.fix .. ' Code actions'))
          -- 一次修复整个文件：收集并应用全部 quickfix（tailwind 任意值批量改名、未用变量等）
          map('n', '<leader>cF', apply_all_quickfix, bufopts(icons.fix .. ' Fix all'))
        end

        if client and client:supports_method('textDocument/codeLens', { bufnr = event.buf }) then
          map({ 'n', 'x' }, 'grx', vim.lsp.codelens.run, bufopts(icons.lsp .. ' Run CodeLens'))
        end

        -- 签名帮助（官方仅 insert 模式绑 <C-S>，normal 无默认）
        map('n', 'gK', vim.lsp.buf.signature_help, bufopts(icons.vscode .. ' Signature help'))

        -- 诊断导航（覆盖 Neovim 内置 `]d`/`[d` 的过长的英文描述）
        map('n', ']d', function() vim.diagnostic.jump({ count = 1 }) end, bufopts('Next diagnostic'))
        map('n', '[d', function() vim.diagnostic.jump({ count = -1 }) end, bufopts('Previous diagnostic'))
        map('n', ']D', function()
          local diag = vim.diagnostic.jump({ count = 1 })
          if diag then vim.api.nvim_win_set_cursor(0, { diag.end_lnum + 1, diag.end_col }) end
        end, bufopts('Next diagnostic end'))
        map('n', '[D', function()
          local diag = vim.diagnostic.jump({ count = -1 })
          if diag then vim.api.nvim_win_set_cursor(0, { diag.end_lnum + 1, diag.end_col }) end
        end, bufopts('Previous diagnostic end'))

        -- 诊断列表
        map('n', '<leader>xx', '<cmd>Trouble diagnostics toggle focus=true filter.buf=0 win.position=bottom<cr>', bufopts(icons.list .. ' Buffer diagnostics'))
        map('n', '<leader>xX', '<cmd>Trouble diagnostics toggle focus=true win.position=bottom<cr>', bufopts(icons.list .. ' Workspace diagnostics'))
        map('n', '<leader>xq', '<cmd>Trouble qflist toggle<cr>', bufopts(icons.list .. ' Quickfix'))
        map('n', '<leader>xQ', function() vim.fn.setqflist({}) vim.cmd('Trouble qflist close') end, bufopts(icons.list .. ' Clear quickfix'))

        -- 重启 LSP
        map('n', '<leader>cR', function()
          local buf = vim.api.nvim_get_current_buf()
          for _, c in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
            local name = c.name
            c:stop()
            vim.defer_fn(function()
              vim.lsp.enable(name)
              vim.notify('LSP restarted: ' .. name)
            end, 500)
          end
        end, bufopts(icons.lsp .. ' Restart LSP'))

      end,
    })
  end,
}
