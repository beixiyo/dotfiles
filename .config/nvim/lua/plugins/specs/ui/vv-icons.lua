-- 共享图标数据（纯 rtp，无 setup 入口）
-- 多个 spec 的文件头部 `require('vv-icons')` 依赖此库先挂 rtp，所以 priority 前置
---@type PackSpec
return {
  desc = '共享图标：files / dirs / extensions / git / ui / diagnostics / kinds',
  url  = 'beixiyo/vv-icons.nvim',
  main = false,
  priority = 1000,
  -- VSCode 白名单 spec 的 keys() 与 config/keymaps 在启动期就读图标
  loadInVSCode = true,
}
