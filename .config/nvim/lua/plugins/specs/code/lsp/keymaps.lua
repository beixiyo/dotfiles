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

local M = {}

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

function M.setup()
  local icons = require('vv-icons')
  local symbols = require('plugins.specs.code.lsp.symbols')

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

      -- go 由全局降级映射管理（LSP→treesitter 降级，见 symbols.lua），这里删掉 Neovim 默认
      pcall(vim.keymap.del, 'n', 'go', { buffer = event.buf })
      map('n', 'gO',  symbols.open_workspace_symbols,  bufopts(icons.vscode .. ' Workspace symbols'))

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
end

return M
