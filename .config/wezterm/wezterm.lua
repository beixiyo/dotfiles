-- ╭─────────────────────────────────────────────────────╮
-- │           WezTerm 配置文件（模块化入口）            │
-- │   实际内容按功能拆分到 modules/*.lua                │
-- ╰─────────────────────────────────────────────────────╯

local wezterm = require('wezterm')
local config = wezterm.config_builder()


-- ──── 模块加载（顺序不重要，各自独立）────
require('modules.appearance').apply(config)
require('modules.window').apply(config)
require('modules.font').apply(config)
require('modules.keys-common').apply(config)


-- ╭─────────────────────────────────────────────────────╮
-- │       Window 管理模式（二选一，注释切换）           │
-- ╰─────────────────────────────────────────────────────╯
-- native：WezTerm 原生 tab + pane（Nvim 内透传 smart-splits）
-- tmux  ：tab / pane 全交给 tmux，由 tmux 条件 bind 无缝切换
--
-- 默认 tmux 模式；切回 WezTerm 原生，注释下面一行、取消注释上面一行

-- require('modules.keys-native').apply(config)
require('modules.keys-tmux').apply(config)


return config
