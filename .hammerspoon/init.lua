-- Move all visible standard windows to the primary display.
local function moveAllWindowsToPrimaryScreen()
  local primaryScreen = hs.screen.primaryScreen()

  if not primaryScreen then
    hs.alert.show('No primary screen found')
    return
  end

  local screenFrame = primaryScreen:frame()
  local offset = 0

  for _, window in ipairs(hs.window.allWindows()) do
    if window:isVisible() and window:isStandard() and not window:isFullScreen() then
      local frame = window:frame()

      frame.w = math.min(frame.w, screenFrame.w - 80)
      frame.h = math.min(frame.h, screenFrame.h - 80)
      frame.x = screenFrame.x + 40 + offset
      frame.y = screenFrame.y + 40 + offset

      window:setFrame(frame, 0)

      offset = (offset + 24) % 240
    end
  end

  hs.alert.show('Windows moved to primary screen')
end

hs.hotkey.bind({ 'ctrl', 'alt', 'shift' }, '-', moveAllWindowsToPrimaryScreen)

-- Alt+Tab → Mission Control（四指上滑的 Overview 视图）
-- 走 Hammerspoon 高层 API，本地物理键盘和 NoMachine 远程都能触发；
-- 远程时需在 NoMachine 菜单(Ctrl+Alt+0) → Input 勾选 "Grab the keyboard input"
hs.hotkey.bind({ 'alt' }, 'tab', function()
  hs.spaces.toggleMissionControl()
end)
