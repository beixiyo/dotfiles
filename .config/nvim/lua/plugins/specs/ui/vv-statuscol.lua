-- 状态列：mark / sign / 行号 / fold / git
---@type PackSpec
return {
  desc = '状态列（mark 字母 / 诊断 sign / 行号 / 折叠图标 / git）',
  url  = 'beixiyo/vv-statuscol.nvim',
  main = 'vv-statuscol',
  -- 不加 cmd/keys/event：必须 eager load，启动时设置 vim.o.statuscolumn
}
