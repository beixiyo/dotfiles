-- Microsoft JavaScript debug adapter for nvim-dap
---@type PackSpec
return {
  desc = 'JavaScript/TypeScript debug adapter',
  url = 'https://github.com/microsoft/vscode-js-debug',
  main = false,

  -- 仅在 DAP 初始化时检查构建并加入 runtime path，不参与 Neovim 启动
  event = 'User DapSetup',

  -- 以 package-lock.json 为安装真源；跳过 postinstall 可避免下载 DAP server 不需要的 Playwright 浏览器
  build = {
    'bash',
    '-lc',
    'npm ci --ignore-scripts && npx gulp dapDebugServer',
  },
}
