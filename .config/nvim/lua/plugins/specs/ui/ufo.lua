-- nvim-ufo：折叠增强
-- 特性：
--   - provider 选择链：lsp → treesitter → indent fallback
--   - 折叠预览：zp 浮窗看折起内容
--   - 虚拟文本：折起首行尾部 "42 lines"
-- 与其他配置：
--   treesitter/lsp 的 foldmethod=expr 会被 ufo 覆盖（它会切 manual 并自行重算）
--   折叠列由 vv-statuscol 通过原生 %C 渲染（foldcolumn=auto:1）
-- 键盘开合折叠后显式重绘 statuscolumn，让原生折叠列立即重算宽度
local function refresh_statuscol()
  pcall(function()
    require('vv-statuscol').refresh()
  end)
end

local function has_closed_folds()
  local line_count = vim.api.nvim_buf_line_count(0)
  for row = 1, line_count do
    if vim.fn.foldclosed(row) > 0 then return true end
  end
  return false
end

local function toggle_all_folds()
  local ufo = require('ufo')
  if has_closed_folds() then
    ufo.openAllFolds()
  else
    ufo.closeAllFolds()
  end
  refresh_statuscol()
end

local function current_fold_buffer()
  local ok, fold = pcall(require, 'ufo.fold')
  local fb = ok and fold.get(vim.api.nvim_get_current_buf()) or nil
  if not fb then
    vim.notify('No ufo folds', vim.log.levels.INFO)
    return
  end
  return fb
end

local function fold_kinds(fb)
  local seen = {}
  local kinds = {}
  for _, range in ipairs(fb.foldRanges or {}) do
    if range.kind and not seen[range.kind] then
      seen[range.kind] = true
      kinds[#kinds + 1] = range.kind
    end
  end
  table.sort(kinds)
  return kinds
end

local function toggle_kind_folds(kinds, label, fb)
  fb = fb or current_fold_buffer()
  if not fb then return end

  local kind_set = {}
  for _, kind in ipairs(kinds) do
    kind_set[kind] = true
  end

  local ranges = {}
  local has_closed = false
  for _, range in ipairs(fb.foldRanges or {}) do
    if range.kind and kind_set[range.kind] then
      local start_lnum = range.startLine + 1
      local end_lnum = range.endLine + 1
      ranges[#ranges + 1] = { start_lnum, end_lnum }
      has_closed = has_closed or fb.foldedLines[start_lnum] ~= false and fb.foldedLines[start_lnum] ~= nil
    end
  end

  if #ranges == 0 then
    vim.notify('No ' .. label .. ' folds', vim.log.levels.INFO)
    return
  end

  if has_closed then
    for _, range in ipairs(ranges) do
      fb:openFold(range[1])
      vim.cmd('silent! ' .. range[1] .. 'foldopen!')
    end
  else
    table.sort(ranges, function(a, b)
      return a[1] == b[1] and a[2] < b[2] or a[1] > b[1]
    end)

    local cmds = {}
    for _, range in ipairs(ranges) do
      fb:closeFold(range[1], range[2])
      cmds[#cmds + 1] = range[1] .. 'foldclose'
    end
    vim.cmd(table.concat(cmds, '|'))
  end

  refresh_statuscol()
end

local function pick_kind_fold()
  local fb = current_fold_buffer()
  if not fb then return end

  local kinds = fold_kinds(fb)
  if #kinds == 0 then
    vim.notify('No fold kinds', vim.log.levels.INFO)
    return
  end

  vim.ui.select(kinds, { prompt = 'Fold kind' }, function(kind)
    if not kind then return end
    toggle_kind_folds({ kind }, kind, fb)
  end)
end

---@type PackSpec
return {
  desc = '折叠增强',
  url = 'https://github.com/kevinhwang91/nvim-ufo',
  main = 'ufo',
  dependencies = { 'https://github.com/kevinhwang91/promise-async' },

  event = { 'BufReadPost', 'BufNewFile' },
  keys = {
    { 'zR', toggle_all_folds,                                                         desc = 'Toggle all folds' },
    { 'zC', function() toggle_kind_folds({ 'comment' }, 'comment') end,               desc = 'Toggle comment folds' },
    { 'zI', function() toggle_kind_folds({ 'imports' }, 'imports') end,               desc = 'Toggle import folds' },
    { 'zK', pick_kind_fold,                                                           desc = 'Pick fold kind' },
    { 'zr', function() require('ufo').openFoldsExceptKinds() refresh_statuscol() end,  desc = 'Open more folds' },
    { 'zm', function() require('ufo').closeFoldsWith() refresh_statuscol() end,        desc = 'Close more folds' },
    { 'zp', function()
        local winid = require('ufo').peekFoldedLinesUnderCursor()
        if not winid then vim.notify('No fold under cursor', vim.log.levels.INFO) end
      end, desc = 'Preview fold' },
  },

  config = function()
    local ufo = require('ufo')
    -- ufo 要求 foldlevel / foldlevelstart 足够大
    vim.o.foldlevel = 99
    vim.o.foldlevelstart = 99
    vim.o.foldenable = true

    -- lsp → treesitter → indent 三级 fallback
    -- 数组写法 { "lsp", "treesitter" } 只支持两级，treesitter 失败会抛 UfoFallbackException
    -- 无法降级，导致切窗口/隐藏 toggleterm 后重算折叠时报错
    local function lsp_ts_indent(bufnr)
      local ufo = require('ufo')
      local function handle(err, next_provider)
        if type(err) == 'string' and err:match('UfoFallbackException') then
          return ufo.getFolds(bufnr, next_provider)
        end
        return require('promise').reject(err)
      end
      return ufo.getFolds(bufnr, 'lsp')
        :catch(function(err) return handle(err, 'treesitter') end)
        :catch(function(err) return handle(err, 'indent') end)
    end

    ---@type UfoConfig
    ufo.setup({
      open_fold_hl_timeout = 150,
      close_fold_kinds_for_ft = {
        default = { 'imports', 'comment' },
        json = { 'array' },
      },
      preview = {
        win_config = {
          border = 'rounded',
          winhighlight = 'Normal:Folded',
          winblend = 0,
        },
        mappings = {
          scrollU = '<C-u>',
          scrollD = '<C-d>',
          jumpTop = '[',
          jumpBot = ']',
        },
      },
      provider_selector = function(_, filetype, buftype)
        -- 特殊 buffer 关掉 ufo（让 statuscol 的 ft_ignore 统一管）
        if buftype ~= '' then return '' end
        -- 新建/空 filetype 的 buffer 没有 LSP/treesitter parser，ufo 会抛 UfoFallbackException 无法降级
        if filetype == '' then return '' end
        return lsp_ts_indent
      end,
    })
  end,
}
