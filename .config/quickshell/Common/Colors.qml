// Colors.qml — 配色来源单例（matugen 动态配色 + Catppuccin 兜底）
//
// 设计：matugen 把当前壁纸配色写到一份 gitignore 的 `colors.json`；这里用 FileView +
// JsonAdapter 读取它。读不到（如全新克隆、还没装/跑过 matugen）时，JsonAdapter 的属性
// 保持下方写死的默认值 —— 即 Catppuccin Mocha 兜底主题。
//
// 因此本文件本身是手维护并提交进仓库的（在模块图里、Theme 解析期就要它存在）；
// 真正每次换壁纸变动的是 colors.json，已 gitignore
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
  id: root

  // 对外暴露的语义配色（字符串 → color 自动转换）
  readonly property color background: adapter.background
  readonly property color surface: adapter.surface
  readonly property color surfaceVariant: adapter.surfaceVariant
  readonly property color primary: adapter.primary
  readonly property color secondary: adapter.secondary
  readonly property color tertiary: adapter.tertiary
  readonly property color error: adapter.error
  readonly property color textPrimary: adapter.textPrimary
  readonly property color textSecondary: adapter.textSecondary
  readonly property color textMuted: adapter.textMuted
  readonly property color outline: adapter.outline

  FileView {
    // 用绝对文件系统路径（Quickshell 的 qs:// 拦截会让 Qt.resolvedUrl 拿不到真实文件路径）
    path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/quickshell/Common/colors.json"
    // 同步加载，避免首帧先闪一下兜底色再跳到 matugen 色
    blockLoading: true
    // 壁纸换色后 matugen 重写 colors.json → 实时重载
    watchChanges: true
    onFileChanged: reload()

    // 默认值 = Catppuccin Mocha 兜底；colors.json 存在时对应键会覆盖这些值
    JsonAdapter {
      id: adapter
      property string background: "#1e1e2e"      // base
      property string surface: "#313244"         // surface0
      property string surfaceVariant: "#45475a"  // surface1
      property string primary: "#89b4fa"         // blue
      property string secondary: "#cba6f7"       // mauve
      property string tertiary: "#94e2d5"        // teal
      property string error: "#f38ba8"           // red
      property string textPrimary: "#cdd6f4"     // text
      property string textSecondary: "#a6adc8"   // subtext0
      property string textMuted: "#6c7086"       // overlay0
      property string outline: "#585b70"         // surface2
    }
  }
}
