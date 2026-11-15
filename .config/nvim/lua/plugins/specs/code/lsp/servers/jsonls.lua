local M = {}

-- 这些扩展名在 filetype.lua 里被归到 json 以复用高亮，但一行一个文档，不是合法的单个 JSON
local LINE_DELIMITED = { jsonl = true, ndjson = true }

function M.setup()
  vim.lsp.config('jsonls', {
    -- 格式化交给 dprint / conform
    init_options = { provideFormatter = false },
    settings = {
      json = { validate = { enable = true } },
    },

    -- 对照表有上千条，推迟到 server 真正启动时再加载，不占启动时间
    before_init = function(_, config)
      config.settings.json.schemas = require('schemastore').json.schemas()
    end,

    root_dir = function(bufnr, on_dir)
      local ext = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ':e')
      if LINE_DELIMITED[ext] then return end
      on_dir(vim.fs.root(bufnr, '.git'))
    end,
  })
end

return M
