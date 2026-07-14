-- 共享工具库。前置加载，让其他 spec / keymap 启动期 require('vv-utils.*') 时就绪
-- 本地开发：vendors/vv-utils.nvim（=stdpath('config')/vendors，见 pack/dev.lua）
-- 存在则 pack.dev 自动重定向，否则 vim.pack 从 GitHub clone 到 site/pack/core/opt
---@type PackSpec
return {
  desc = '共享工具：path / yaml / ui-window / scroll / bigfile 等',
  url  = 'beixiyo/vv-utils.nvim',
  main = 'vv-utils',
  priority = 1000,

  config = function()
    -- 启用带副作用的子模块；纯函数模块（path / fs / hl ...）无需在此声明
    ---@type vv-utils.Opts
    require('vv-utils').setup({
      drop    = true, -- 终端拖拽路径检测（vim.paste 拦截）
      bigfile = true, -- 大文件保护
      format  = true, -- 注册 :VVAddSpaces / :VVCleanTrailing
      scroll  = not vim.g.neovide, -- 键盘滚动和视口跳转动画（Neovide 自带 GPU 平滑滚动，不接管）
    })
  end,
}
