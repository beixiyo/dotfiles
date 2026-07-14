-- lua_ls 性能调优
-- workspace.library 由 pack.luarc 自动生成到 .luarc.json，这里只管运行时行为
--
-- 3.16.x 有严重性能退步（https://github.com/LuaLS/lua-language-server/issues/3322）
-- 如果依然卡顿，降级到 3.15.0：
--   :MasonUninstall lua-language-server
--   :MasonInstall lua-language-server@3.15.0
return {
  settings = {
    Lua = {
      workspace = {
        -- 限制预加载文件数量和大小，避免启动时全量扫描导致卡顿
        maxPreload = 1000,
        preloadFileSize = 500,
        checkThirdParty = false,
      },
      -- 关闭语义 token（treesitter 已覆盖，减少 lua_ls 计算量）
      semantic = { enable = false },
      -- 关闭 inlay hints（行内参数名/类型标注），非诊断，减少计算
      hint = { enable = false },
      diagnostics = {
        -- 不扫描 library 文件（主要性能瓶颈），只诊断自己的代码
        libraryFiles = 'Disable',
        -- 不扫描未打开的工作区文件
        workspaceEvent = 'None',
      },
    },
  },
}
