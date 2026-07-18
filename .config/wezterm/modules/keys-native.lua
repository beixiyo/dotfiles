-- ╭───────────────────────────────────────────────────────────────╮
-- │    native 模式（WezTerm 原生 tab + pane，集成 smart-splits）  │
-- ╰───────────────────────────────────────────────────────────────╯
-- 机制：检测前台进程是否为 nvim，是则透传键给 nvim（smart-splits 接管），
-- 否则执行 WezTerm 原生 pane 操作

local wezterm = require('wezterm')
local act = wezterm.action

local M = {}

local function is_nvim(pane)
  return (pane:get_foreground_process_name() or ''):find('[/\\]n?vim') ~= nil
end

-- Ctrl+Alt+h/j/k/l：Nvim 内交给 smart-splits，否则切换 WezTerm 窗格
local function nav_or_pane(direction, key)
  return {
    key = key, mods = 'CTRL|ALT',
    action = wezterm.action_callback(function(win, pane)
      if is_nvim(pane) then
        win:perform_action(act.SendKey { key = key, mods = 'CTRL|ALT' }, pane)
      else
        win:perform_action(act.ActivatePaneDirection(direction), pane)
      end
    end),
  }
end

-- Ctrl+Alt+方向键：Nvim 内交给 smart-splits，否则调整窗格大小
local function resize_or_nvim(direction, arrow_key)
  return {
    key = arrow_key, mods = 'CTRL|ALT',
    action = wezterm.action_callback(function(win, pane)
      if is_nvim(pane) then
        win:perform_action(act.SendKey { key = arrow_key, mods = 'CTRL|ALT' }, pane)
      else
        win:perform_action(act.AdjustPaneSize { direction, 3 }, pane)
      end
    end),
  }
end

function M.apply(config)
  config.keys = config.keys or {}
  local keys = {
    -- ── Tab 管理（WezTerm 原生 tab，tmux 模式下改用 tmux window）──
    { key = 'T', mods = 'CTRL|SHIFT', action = act.SpawnTab('DefaultDomain') },
    { key = 'w', mods = 'CTRL|SHIFT', action = act.CloseCurrentTab { confirm = false } },

    -- ── 分屏创建 / 关闭（WezTerm 原生 pane）──
    { key = '-',  mods = 'CTRL|ALT', action = act.SplitVertical   { domain = 'CurrentPaneDomain' } },
    { key = '\\', mods = 'CTRL|ALT', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
    { key = 'w',  mods = 'CTRL|ALT', action = act.CloseCurrentPane { confirm = false } },

    -- ── 分屏导航（Nvim 内透传给 smart-splits，否则切 WezTerm pane）──
    nav_or_pane('Left',  'h'),
    nav_or_pane('Down',  'j'),
    nav_or_pane('Up',    'k'),
    nav_or_pane('Right', 'l'),

    resize_or_nvim('Left',  'LeftArrow'),
    resize_or_nvim('Down',  'DownArrow'),
    resize_or_nvim('Up',    'UpArrow'),
    resize_or_nvim('Right', 'RightArrow'),
  }
  for _, k in ipairs(keys) do
    table.insert(config.keys, k)
  end

  -- Ctrl + 数字键切换 Tab（1~8），WezTerm Tab 索引从 0 开始
  for i = 1, 8 do
    table.insert(config.keys, {
      key = tostring(i),
      mods = 'CTRL',
      action = act.ActivateTab(i - 1),
    })
  end
end

return M
