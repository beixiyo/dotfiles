-- mini.surround：加/删/换外围字符（括号、引号、标签）
--
-- 用法（按键前缀 gs*）：
--   gsa  + char  → 加包裹：可视模式选中后按；或普通模式下在单词上按 (如 gsaw → 当前词加 "  )
--   gsd  + char  → 删包裹：光标在括号内按 gsd) 删掉这对括号
--   gsr  + old new → 换包裹：gsr)' 把 () 换成 ''
--   gsf  + char  → 向右找外围字符（光标跳到匹配的右侧包围）
--   gsF  + char  → 向左找
--   gsh          → 高亮光标处的包裹字符
--   后缀：l (最后一个) / n (下一个)，配合 gsf/gsF 过滤多个候选
--   标签：gsat 给当前节点加 <div> 标签；输入 <div 后按 Tab 补属性，> 结束
--        gsdt 删标签、gsrt 换标签
--
--   例子（光标在 hi 上）：
--     gsd)   删 (hi)  → hi
--     gsaiw) 给 hi 加 () → (hi)
--     gsr"'  把 "hi" 换成 'hi'
--
-- 键位前缀 gs*：与 flash 的 s/S 错开，和 LazyVim extras/coding/mini-surround 同款
---@type PackSpec
return {
  desc = '周围包裹增删改',
  url = 'https://github.com/nvim-mini/mini.surround',
  main = 'mini.surround',
  loadInVSCode = true,

  event = { 'BufReadPost', 'BufNewFile' },

  opts = {
    mappings = {
      add = 'gsa', delete = 'gsd', replace = 'gsr',
      find = 'gsf', find_left = 'gsF', highlight = 'gsh',
      suffix_last = 'l', suffix_next = 'n',
    },
    highlight_duration = 800,
    silent = false,
  },
}
