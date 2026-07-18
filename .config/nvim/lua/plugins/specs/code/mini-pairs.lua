-- mini.pairs：自动补全引号、括号等配对字符
---@type PackSpec
return {
  desc = '自动括号/引号配对',
  url = 'https://github.com/nvim-mini/mini.pairs',
  main = 'mini.pairs',

  opts = {
    modes = { insert = true, command = true, terminal = true },
    -- 下一个字符是字母数字、引号、句号等时不自动补全
    skip_next = [=[[%w%%%'%[%"%.%`%$]]=],
    -- 在 Tree-sitter 识别的字符串节点内不配对
    skip_ts = { 'string' },
    skip_unbalanced = true,
    markdown = true,
  },

  config = function(_, opts)
    local mini_pairs = require('mini.pairs')
    mini_pairs.setup(opts)

    -- mini.pairs 原生只认 modes/mappings，skip_next/skip_ts/skip_unbalanced/markdown
    -- 需自行在 open 外层实现（逻辑参考 LazyVim lua/lazyvim/util/mini.lua）
    local open = mini_pairs.open
    mini_pairs.open = function(pair, neigh_pattern)
      if vim.fn.getcmdline() ~= '' then
        return open(pair, neigh_pattern)
      end

      local o, c = pair:sub(1, 1), pair:sub(2, 2)
      local line = vim.api.nvim_get_current_line()
      local cursor = vim.api.nvim_win_get_cursor(0)
      local next = line:sub(cursor[2] + 1, cursor[2] + 1)
      local before = line:sub(1, cursor[2])

      if opts.markdown and o == '`' and vim.bo.filetype == 'markdown' and before:match('^%s*``') then
        return '`\n```' .. vim.api.nvim_replace_termcodes('<up>', true, true, true)
      end

      if opts.skip_next and next ~= '' and next:match(opts.skip_next) then
        return o
      end

      if opts.skip_ts and #opts.skip_ts > 0 then
        local ok, captures = pcall(vim.treesitter.get_captures_at_pos, 0, cursor[1] - 1, math.max(cursor[2] - 1, 0))
        for _, capture in ipairs(ok and captures or {}) do
          if vim.tbl_contains(opts.skip_ts, capture.capture) then
            return o
          end
        end
      end

      if opts.skip_unbalanced and next == c and c ~= o then
        local _, count_open = line:gsub(vim.pesc(pair:sub(1, 1)), '')
        local _, count_close = line:gsub(vim.pesc(pair:sub(2, 2)), '')
        if count_close > count_open then
          return o
        end
      end

      return open(pair, neigh_pattern)
    end

    local undo_break = vim.api.nvim_replace_termcodes('<C-g>u', true, false, true)

    for key, pair_info in pairs(mini_pairs.config.mappings) do
      local info = pair_info

      vim.keymap.set('i', key, function()
        return mini_pairs[info.action](info.pair, info.neigh_pattern) .. undo_break
      end, {
        expr = true,
        replace_keycodes = false,
        desc = 'Pair with undo break',
      })
    end
  end,
}
