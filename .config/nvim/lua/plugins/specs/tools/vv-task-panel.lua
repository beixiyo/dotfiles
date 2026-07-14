-- vv-task-panel：可扩展任务面板（provider 模式，默认启用 npm provider）
---@type PackSpec
return {
  desc = '可扩展的任务面板（TS monorepo scripts）',
  url  = 'beixiyo/vv-task-panel.nvim',
  main = 'vv-task-panel',
  dependencies = { 'beixiyo/vv-utils.nvim', 'beixiyo/vv-icons.nvim' },

  cmd = { 'VVTaskPanel', 'VVTaskPanelOpen', 'VVTaskPanelClose', 'VVTaskPanelRefresh', 'VVTaskPanelTasks', 'VVTaskPanelRunLine' },
  -- BufEnter 兜底：经 vv-explorer 预览打开文件时，bufload 在非 nested 的 CursorMoved 回调里触发，
  -- 其 BufReadPost 被 autocmd 嵌套规则吞掉，真正 promote 只触发 BufEnter，故两类事件都挂上才能可靠懒加载
  event = {
    'BufReadPost */package.json', 'BufReadPost */deno.json', 'BufReadPost */deno.jsonc',
    'BufEnter */package.json', 'BufEnter */deno.json', 'BufEnter */deno.jsonc',
  },
  keys = {
    { '<leader>tp', '<cmd>VVTaskPanel<cr>',      desc = 'Task panel' },
    { '<leader>tl', '<cmd>VVTaskPanelTasks<cr>', desc = 'Task list' },
  },

  ---@type VVTaskPanelConfig
  opts = {
    width = 44,
    position = 'right',
    term_position = 'bottom',
    term_height = 15,
    exclude_dirs = { 'node_modules', '.git', 'dist', 'build', '.next', '.turbo', '.cache', 'coverage', '.nuxt', 'out' },
  },
}
