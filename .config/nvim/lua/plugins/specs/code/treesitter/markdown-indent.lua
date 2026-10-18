-- markdown 的 indentexpr：只在注入语言（围栏代码块）内委托 nvim-treesitter 缩进
-- markdown 自身的 indents query 缺失/只有 list_item @indent.auto，直接挂 get_indent 会让正文行缩进归零
-- 因此注入语言外一律返回 -1（沿用 autoindent 复制上一行缩进）
local M = {}

local HOST_LANGS = { markdown = true, markdown_inline = true }

--- 供 indentexpr 调用：lnum 落在非 markdown 的注入树内时用该语言的 indents query，否则保持 autoindent
---@param lnum integer 1-based 行号
---@return integer
function M.get_indent(lnum)
  local ok, parser = pcall(vim.treesitter.get_parser, 0)
  if not ok or not parser then return -1 end

  parser:parse({ lnum - 1, lnum })

  local range = { lnum - 1, 0, lnum - 1, 0 }
  local lang = parser:language_for_range(range):lang()
  if HOST_LANGS[lang] then return -1 end

  return require('nvim-treesitter.indent').get_indent(lnum)
end

return M
