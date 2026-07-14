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
}
