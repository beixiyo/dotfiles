-- ================================
-- nvim-notify 高亮主题（tokyonight 内置 extra，本项目未自己修改）
--
-- 这些 Notify{LEVEL}{Body,Border,Icon,Title} 高亮组来自 rcarriga/nvim-notify
-- 插件，渲染右上角那种"带边框浮窗 + 图标 + 标题 + 正文 + 渐隐动画"的通知卡片
--
-- 本项目实际的触发链：
--   1. 代码调用 vim.notify(msg, level, opts)
--   2. noice.nvim 在 VimEnter 后劫持 vim.notify（见 noice/init.lua:23 M.enable）
--   3. noice 默认把消息路由给 nvim-notify 渲染（nvim-notify 是 noice 的 dep
--      之一，见 registry.lua 的 noice 条目 deps 列表）
--   4. nvim-notify 用这里定义的 NotifyXXX 高亮组上色
-- 所以：本项目未显式安装 nvim-notify，但它随 noice 一并被 vim.pack 拉下来，
-- 视觉风格完全由本文件（tokyonight.groups.notify）统一
-- 只有当 noice 还没 enable（启动极早期）时，vim.notify 才会退化成原生
-- nvim_echo 行为，此时本文件不生效
-- ================================

local Util = require("tokyonight.util")

local M = {}

M.url = "https://github.com/rcarriga/nvim-notify"

---@type tokyonight.HighlightsFn
function M.get(c, opts)
  -- stylua: ignore
  return {
    NotifyBackground  = { fg = c.fg, bg = c.bg },
    NotifyDEBUGBody   = { fg = c.fg, bg = opts.transparent and c.none or c.bg },
    NotifyDEBUGBorder = { fg = Util.blend_bg(c.comment, 0.3), bg = opts.transparent and c.none or c.bg },
    NotifyDEBUGIcon   = { fg = c.comment },
    NotifyDEBUGTitle  = { fg = c.comment },
    NotifyERRORBody   = { fg = c.fg, bg = opts.transparent and c.none or c.bg },
    NotifyERRORBorder = { fg = Util.blend_bg(c.error, 0.3), bg = opts.transparent and c.none or c.bg },
    NotifyERRORIcon   = { fg = c.error },
    NotifyERRORTitle  = { fg = c.error },
    NotifyINFOBody    = { fg = c.fg, bg = opts.transparent and c.none or c.bg },
    NotifyINFOBorder  = { fg = Util.blend_bg(c.info, 0.3), bg = opts.transparent and c.none or c.bg },
    NotifyINFOIcon    = { fg = c.info },
    NotifyINFOTitle   = { fg = c.info },
    NotifyTRACEBody   = { fg = c.fg, bg = opts.transparent and c.none or c.bg },
    NotifyTRACEBorder = { fg = Util.blend_bg(c.purple, 0.3), bg = opts.transparent and c.none or c.bg },
    NotifyTRACEIcon   = { fg = c.purple },
    NotifyTRACETitle  = { fg = c.purple },
    NotifyWARNBody    = { fg = c.fg, bg = opts.transparent and c.none or c.bg },
    NotifyWARNBorder  = { fg = Util.blend_bg(c.warning, 0.3), bg = opts.transparent and c.none or c.bg },
    NotifyWARNIcon    = { fg = c.warning },
    NotifyWARNTitle   = { fg = c.warning },
  }
end

return M
