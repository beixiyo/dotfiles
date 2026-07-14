-- vv-flow.nvim — 流程 / TODO 标记高亮 + 可排序跳转面板（自实现，仅依赖 ripgrep）
---@type PackSpec
return {
  desc = '流程/TODO 标记高亮 + 跳转面板',
  url  = 'beixiyo/vv-flow.nvim',
  main = 'vv-flow',
  dependencies = { 'beixiyo/vv-utils.nvim', 'beixiyo/vv-icons.nvim' },

  -- 实时高亮要随文件打开生效 → event 懒加载；面板命令 / 键位一并注册
  event = { 'BufReadPost', 'BufNewFile' },
  cmd = { 'VVFlow', 'VVFlowOpen', 'VVFlowClose', 'VVFlowRefresh', 'VVFlowEnable', 'VVFlowDisable', 'VVFlowToggle' },
  keys = function()
    return {
      { '<leader>ft', '<cmd>VVFlow<cr>', mode = 'n', desc = require('vv-icons').marks .. ' TODO panel' },
    }
  end,

  ---@type VVFlowConfig
  opts = {},
}
