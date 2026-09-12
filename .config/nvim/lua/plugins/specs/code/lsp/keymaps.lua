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
-- 策略：gr* 前缀沿用官方，位置和列表 UI 统一交给 vv-symbols

local M = {}
local Hover = require('plugins.specs.code.lsp.hover')

-- 一次性安全应用当前文件全部可编辑修复，保留 buffer modified 状态
--
-- on_conflict = 'skip'：LSP 常给出互斥的备选修复（如 tailwind 对同义类既提供
-- 「删 A」也提供「删 B」），范围重叠。整体放弃会导致一个都改不了，这里改为
-- 先到先得，重叠的候选跳过并在通知里报数，剩余修复照常应用
local function apply_all_quickfix()
  local result = require('vv-utils.lsp.code_actions').fix_document({
    bufnr = vim.api.nvim_get_current_buf(),
    save = false,
    on_conflict = 'skip',
  })
  if result.error then
    local level = result.error.code == 'no_quickfixes' and vim.log.levels.INFO or vim.log.levels.WARN
    return vim.notify(result.error.message, level)
  end

  local skipped = result.skipped_count or 0
  local message = ('Applied %d fixes'):format(result.edits_count)
  if skipped > 0 then message = ('%s, skipped %d conflicting'):format(message, skipped) end
  vim.notify(message, skipped > 0 and vim.log.levels.WARN or vim.log.levels.INFO)
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

      -- 跳转类：查询光标所在标识符，位置列表统一由 vv-symbols 展示
      local function open_locations(method)
        -- vv-symbols 和 vv-explorer 都在左侧，避免同时占用
        pcall(function()
          local explorer = package.loaded['vv-explorer']
          if explorer and explorer.is_open() then explorer.close() end
        end)
        if method == 'references' then
          require('vv-symbols').references({ buf = event.buf })
        else
          require('vv-symbols').locations({ buf = event.buf, method = method })
        end
      end

      map('n', 'gd', function() open_locations('definition') end, bufopts(icons.jumps .. ' Definitions'))
      map('n', 'gD', function() open_locations('declaration') end, bufopts(icons.jumps .. ' Declarations'))
      map('n', 'grr', function() open_locations('references') end, bufopts(icons.jumps .. ' References'))
      map('n', 'gri', function() open_locations('implementation') end, bufopts(icons.jumps .. ' Implementations'))
      map('n', 'grt', function() open_locations('type_definition') end, bufopts(icons.jumps .. ' Type definitions'))

      -- go 由全局降级映射管理（LSP→treesitter 降级，见 symbols.lua），这里删掉 Neovim 默认
      pcall(vim.keymap.del, 'n', 'go', { buffer = event.buf })
      map('n', 'gO', symbols.open_workspace_symbols, bufopts(icons.vscode .. ' Workspace symbols'))

      -- K：悬停信息（覆盖默认，"再按一次关闭"切换行为）
      map('n', 'K', Hover.toggle, vim.tbl_extend('force', bufopts(icons.vscode .. ' Toggle hover'), { silent = true }))

      -- 操作类
      if client and client:supports_method('textDocument/rename', { bufnr = event.buf }) then
        map('n', 'grn', vim.lsp.buf.rename, bufopts(icons.rename .. ' Rename'))
      end
      if client and client:supports_method('textDocument/codeAction', { bufnr = event.buf }) then
        map({ 'n', 'x' }, 'gra', vim.lsp.buf.code_action, bufopts(icons.fix .. ' Code actions'))
        -- 整理导入独立于修复错误；仅一个候选时直接应用，多个候选仍由用户选择
        map('n', '<leader>co', function()
          vim.lsp.buf.code_action({
            context = { only = { 'source.organizeImports' }, diagnostics = {} },
            apply = true,
          })
        end, bufopts(icons.fix .. ' Organize imports'))
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
      map(
        'n',
        '<leader>xx',
        function() require('vv-symbols').diagnostics({ buf = 0, toggle = true }) end,
        bufopts(icons.list .. ' Buffer diagnostics')
      )
      map(
        'n',
        '<leader>xX',
        function() require('vv-symbols').diagnostics({ toggle = true }) end,
        bufopts(icons.list .. ' Workspace diagnostics')
      )
      map(
        'n',
        '<leader>xq',
        function() require('vv-symbols').quickfix({ toggle = true }) end,
        bufopts(icons.list .. ' Quickfix')
      )
      map('n', '<leader>xQ', function()
        vim.fn.setqflist({}, 'r', {})
        require('vv-symbols').close()
      end, bufopts(icons.list .. ' Clear quickfix'))

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
