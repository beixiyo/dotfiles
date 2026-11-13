local function smart_close_floats(fallback)
  return function()
    if fallback == "<Esc>" then
      require('config.keymaps.multicursor').clear()
    end

    local closed = false
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
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(fallback, true, false, true), "n", false)
    end
  end
end

vim.keymap.set("n", "<Esc>", smart_close_floats("<Esc>"), { desc = "Close float or clear search" })
vim.keymap.set("n", "q", smart_close_floats("q"), { desc = "Close float or record macro" })
