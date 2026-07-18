-- ╭─────────────────────────────────────────────────────╮
-- │          tmux 模式（键原样透传给 tmux）              │
-- ╰─────────────────────────────────────────────────────╯
-- 本模式下 WezTerm 不再拦截 tab / 分屏键，全部透传给 tmux。
-- tmux 负责：ctrl+alt+hjkl 切 pane（条件 bind 按 @pane-is-vim 透传 nvim 或 select-pane）、
--            ctrl+shift+t / ctrl+1..8 / ctrl+shift+w 切 window
--
-- 约定：tmux 模式下不使用 WezTerm 原生 tab/pane（用 tmux 的 window/pane 代替），
--       启动时一般直接跑 `tmux new-session -A` 进入主 session

local wezterm = require('wezterm')
local act = wezterm.action

local M = {}

function M.apply(config)
  -- 显式发 CSI u 序列透传 tab 管理键给 tmux，对齐终端原生快捷键体验。
  -- 为什么不用 DisableDefaultAssignment：
  --   仅 Disable 后 WezTerm 走 legacy 编码（ctrl+1 → '1'，ctrl+shift+t → 'T'），
  --   tmux 无法与普通输入区分，bind-key -n C-1 / C-S-t 不会触发。
  --   显式发 CSI u 绕开协议协商，tmux 的 extended-keys 直接识别。
  -- 格式：\x1b[<codepoint>;<modifier>u
  --   modifier = 1 + Shift(1) + Alt(2) + Ctrl(4)
  --   116='t' 119='w' 49..56='1'..'8'；Ctrl+Shift=6，Ctrl=5

  config.keys = config.keys or {}

  local passthrough = {
    { key = 'Tab', mods = 'CTRL', seq = '\x1b[9;5u' },
    { key = 'T', mods = 'CTRL|SHIFT', seq = '\x1b[116;6u' },
    { key = 't', mods = 'CTRL|SHIFT', seq = '\x1b[116;6u' },
    { key = 'W', mods = 'CTRL|SHIFT', seq = '\x1b[119;6u' },
    { key = 'w', mods = 'CTRL|SHIFT', seq = '\x1b[119;6u' },
  }
  for _, k in ipairs(passthrough) do
    table.insert(config.keys, {
      key = k.key, mods = k.mods,
      action = act.SendString(k.seq),
    })
  end

  for i = 1, 8 do
    table.insert(config.keys, {
      key = tostring(i), mods = 'CTRL',
      action = act.SendString(string.format('\x1b[%d;5u', 48 + i)),
    })
  end

  -- Ctrl+Alt+* pane 管理键：同 Ctrl+Shift+T 等，Windows/Linux 下 Ctrl+Alt 被
  -- AltGr 转换或 Win32 input mode 截断，tmux 收不到正确序列
  -- 改为显式发 CSI u 绕开平台差异（modifier=7: 1+Alt2+Ctrl4）
  local pane_keys = {
    { key = '\\', mods = 'CTRL|ALT', codepoint = 92  },  -- 横向分屏
    { key = '-',  mods = 'CTRL|ALT', codepoint = 45  },  -- 纵向分屏
    { key = 'w',  mods = 'CTRL|ALT', codepoint = 119 },  -- 关闭 pane
    { key = 'h',  mods = 'CTRL|ALT', codepoint = 104 },  -- 焦点左
    { key = 'j',  mods = 'CTRL|ALT', codepoint = 106 },  -- 焦点下
    { key = 'k',  mods = 'CTRL|ALT', codepoint = 107 },  -- 焦点上
    { key = 'l',  mods = 'CTRL|ALT', codepoint = 108 },  -- 焦点右
  }
  for _, k in ipairs(pane_keys) do
    table.insert(config.keys, {
      key = k.key, mods = k.mods,
      action = act.SendString(string.format('\x1b[%d;7u', k.codepoint)),
    })
  end

  -- Arrow 键格式不同：\x1b[1;<mod><dir>（mod=7 同上）
  local arrow_keys = {
    { key = 'LeftArrow',  seq = '\x1b[1;7D' },
    { key = 'DownArrow',  seq = '\x1b[1;7B' },
    { key = 'UpArrow',    seq = '\x1b[1;7A' },
    { key = 'RightArrow', seq = '\x1b[1;7C' },
  }
  for _, k in ipairs(arrow_keys) do
    table.insert(config.keys, {
      key = k.key, mods = 'CTRL|ALT',
      action = act.SendString(k.seq),
    })
  end

  -- Ctrl+Shift+Tab 无对应 tmux 绑定，禁用 WezTerm 默认行为
  local disabled = {
    { key = 'Tab', mods = 'CTRL|SHIFT' },
  }
  for _, k in ipairs(disabled) do
    table.insert(config.keys, {
      key = k.key, mods = k.mods,
      action = act.DisableDefaultAssignment,
    })
  end
end

return M
