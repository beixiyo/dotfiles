local function smart_close_floats(fallback)
  return function()
    if fallback == "<Esc>" then
      require('config.keymaps.multicursor').clear()
    end

    -- hover 文档先交给它自己的关闭逻辑：直接关窗口只会关掉内容窗口，
    -- noice 的边框窗口不可聚焦，会被下面的筛选跳过而残留在屏幕上
    local closed = require('plugins.specs.code.lsp.hover').close()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local ok, cfg = pcall(vim.api.nvim_win_get_config, win)
      -- 只关可交互的浮窗：treesitter-context、滚动条等不可聚焦的装饰浮窗常驻
      -- 把它们算进来会让 q 永远录不了宏、<Esc> 永远清不掉搜索高亮
      if ok and cfg and cfg.relative ~= "" and cfg.focusable ~= false and not cfg.hide then
        pcall(vim.api.nvim_win_close, win, true)
        closed = true
      end
    end

    if not closed then
      if fallback == "<Esc>" and vim.v.hlsearch == 1 then
        vim.cmd("nohlsearch")
      end
      -- i：插到 typeahead 最前面，否则快速输入 qa 时 q 会排到 a 之后
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(fallback, true, false, true), "in", false)
    end
  end
end

vim.keymap.set("n", "<Esc>", smart_close_floats("<Esc>"), { desc = "Close float or clear search" })
vim.keymap.set("n", "q", smart_close_floats("q"), { desc = "Close float or record macro" })
