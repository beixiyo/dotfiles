-- ╭─────────────────────────────────────────────────────╮
-- │      基础快捷键（真·通用，不随 tmux 模式变化）      │
-- ╰─────────────────────────────────────────────────────╯
-- Tab 管理 / 分屏创建已分别移至 standalone-keymap.lua 或 tmux-keymap.lua，
-- 保证「二选一」互斥：终端自管 tab ↔ tmux 管 window
-- 字体缩放 / CSI u 透传 / 新 OS 窗口 / 鼠标

local wezterm = require('wezterm')
local act = wezterm.action

local M = {}

function M.apply(config)
  -- 启用 kitty keyboard protocol（精确修饰键上报，修正 Ctrl+hjkl 等）
  config.enable_kitty_keyboard = true

  -- Shift+点击透传给 nvim（默认 WezTerm 用 Shift 做 bypass 做自己选中）
  config.bypass_mouse_reporting_modifiers = 'ALT'

  -- Shell 默认目录
  local home = os.getenv('HOME') or os.getenv('USERPROFILE')
  config.default_cwd = home .. '/Documents/code/frontend'

  -- 鼠标
  config.selection_word_boundary = 'fast'
  config.mouse_bindings = {
    {
      event = { Down = { streak = 1, button = 'Right' } },
      mods = 'NONE',
      action = act.PasteFrom('Clipboard'),
    },
  }

  -- Windows 上 Wayland 禁用（兼容性问题）
  if wezterm.os == 'Windows' then
    config.enable_wayland = false
  end

  config.keys = config.keys or {}

  local base_keys = {
    -- ── 禁用 macOS 默认 Cmd+T / Cmd+W（避免菜单抢键）──
    { key = 't', mods = 'CMD', action = act.DisableDefaultAssignment },
    { key = 'w', mods = 'CMD', action = act.DisableDefaultAssignment },

    -- ── 字体缩放 ──
    { key = '=', mods = 'CTRL', action = act.IncreaseFontSize },
    { key = '-', mods = 'CTRL', action = act.DecreaseFontSize },
    { key = '0', mods = 'CTRL', action = act.ResetFontSize },

    -- ── 透传给 Neovim 的特殊键（CSI u 直注入，绕过 tmux 重编码）──
    { key = '`', mods = 'CTRL',       action = act.SendString('\x1b[96;5u') },  -- Ctrl+`
    { key = 'L', mods = 'CTRL|SHIFT', action = act.SendString('\x1b[108;6u') }, -- Ctrl+Shift+l

    -- ── Shift+Enter 换行（Claude Code 等 TUI）──
    -- 默认走 legacy 编码与普通 Enter(\r) 无法区分 → 被当成提交；
    -- 显式发 CSI u（13=Enter，modifier 2=Shift）→ 换行
    { key = 'Enter', mods = 'SHIFT', action = act.SendString('\x1b[13;2u') },

    -- ── 其他 ──
    { key = 'N', mods = 'CTRL|SHIFT', action = act.SpawnWindow },
    { key = 'M', mods = 'CTRL|SHIFT', action = act.ShowLauncher },
  }

  for _, k in ipairs(base_keys) do
    table.insert(config.keys, k)
  end
end

return M
