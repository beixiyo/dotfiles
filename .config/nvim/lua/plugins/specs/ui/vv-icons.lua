-- 共享图标数据（纯 rtp，无 setup 入口）
-- 多个 spec 的文件头部 `require('vv-icons')` 依赖此库先挂 rtp，所以 priority 前置
---@type PackSpec
return {
  desc = '共享图标：files / dirs / extensions / git / ui / diagnostics / kinds',
  url  = 'beixiyo/vv-icons.nvim',
  main = false,
  priority = 1000,
}
