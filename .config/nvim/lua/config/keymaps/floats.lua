local map = require("config.keymaps.helpers").map

local function smart_close_floats(fallback)
  return function()
    local closed = false
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local ok, cfg = pcall(vim.api.nvim_win_get_config, win)
      if ok and cfg and cfg.relative ~= "" then
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

map("n", "yy", "^yg_", { desc = "Copy trimmed line" })
