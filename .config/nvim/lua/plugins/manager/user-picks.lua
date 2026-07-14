-- ================================
-- 插件禁用表（:PluginManager 勾选后写入，可手动编辑）
-- ================================
-- 默认全部启用；只在此列出要 *禁用* 的插件：[id] = false
-- 禁用后在新环境不会自动安装，已经安装的不会删除，删除 spec 文件后才会自动删除插件
-- 已启用的无需列出。修改后重启 Neovim 生效

return {
  ["agentic"] = false,
  ["bufferline"] = false,
  ["comment"] = false,
  ["fff"] = false,
  ["im-select"] = false,
}
