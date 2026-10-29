-- ╭─────────────────────────────────────────────────────╮
-- │                    快捷键                           │
-- ╰─────────────────────────────────────────────────────╯

-- Tab：新建、关闭、按序号切换
rex.bind("ctrl+shift+t", "client.tab.new")
rex.bind("ctrl+shift+w", "client.tab.close")

for index = 1, 8 do
  rex.bind("ctrl+" .. index, "client.tab.goto", { index = index })
end

-- 窗格：上下分屏、左右分屏、关闭、放大和恢复
rex.bind("ctrl+alt+-", "pane.split", { direction = "down" })
rex.bind("ctrl+alt+[Backslash]", "pane.split", { direction = "right" })
rex.bind("ctrl+alt+w", "pane.close")
rex.bind("ctrl+alt+b", "pane.zoom")

-- 窗格：按方向切换，不循环到另一侧
rex.bind("ctrl+alt+h", "pane.focus", { direction = "left", wrap = false })
rex.bind("ctrl+alt+j", "pane.focus", { direction = "down", wrap = false })
rex.bind("ctrl+alt+k", "pane.focus", { direction = "up", wrap = false })
rex.bind("ctrl+alt+l", "pane.focus", { direction = "right", wrap = false })

-- 窗格：按方向移动分割线
rex.bind("ctrl+alt+left", "pane.resize", { direction = "left" })
rex.bind("ctrl+alt+down", "pane.resize", { direction = "down" })
rex.bind("ctrl+alt+up", "pane.resize", { direction = "up" })
rex.bind("ctrl+alt+right", "pane.resize", { direction = "right" })

-- 字体缩放
rex.bind("ctrl+=", "client.font.increase")
rex.bind("ctrl+-", "client.font.decrease")
rex.bind("ctrl+0", "client.font.reset")

-- 新建窗口
rex.bind("ctrl+shift+n", "client.window.new")
