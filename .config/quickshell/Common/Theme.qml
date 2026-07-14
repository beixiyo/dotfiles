// Theme.qml — 全局设计系统单例
//
// 把 matugen 生成的原始配色（Colors 单例，同目录可直接按名访问）做语义化映射，
// 并集中管理间距、圆角、字号、动画时长等设计 token。所有组件统一 `import qs.Common`
// 后用 `Theme.primary` / `Theme.spacingM` 等访问，做到一处定义、全局复用
pragma Singleton

import QtQuick
import Quickshell

Singleton {
  id: root

  // ============ 语义配色（映射自 matugen） ============
  readonly property color background: Colors.background
  readonly property color surface: Colors.surface
  readonly property color surfaceVariant: Colors.surfaceVariant
  readonly property color primary: Colors.primary
  readonly property color secondary: Colors.secondary
  readonly property color tertiary: Colors.tertiary
  readonly property color error: Colors.error
  readonly property color textPrimary: Colors.textPrimary
  readonly property color textSecondary: Colors.textSecondary
  readonly property color textMuted: Colors.textMuted
  readonly property color outline: Colors.outline

  // 派生语义色（不随壁纸变化的固定语义）
  readonly property color success: "#2e9d63"
  readonly property color warning: "#c57f1b"

  // ============ 玻璃拟态 ============
  readonly property color glassBorder: alpha(primary, 0.35)
  readonly property color glassHighlight: alpha("#ffffff", 0.12)
  readonly property color shadowColor: alpha("#000000", 0.55)

  // ============ 字号 ============
  readonly property int fontSizeXS: 10
  readonly property int fontSizeS: 11
  readonly property int fontSizeM: 12
  readonly property int fontSizeL: 14
  readonly property int fontSizeXL: 16
  readonly property int fontSizeHuge: 28

  // ============ 间距 ============
  readonly property int spacingXS: 4
  readonly property int spacingS: 6
  readonly property int spacingM: 10
  readonly property int spacingL: 14
  readonly property int spacingXL: 20

  // ============ 圆角 ============
  readonly property int radiusS: 6
  readonly property int radiusM: 10
  readonly property int radiusL: 14
  readonly property int radiusXL: 20
  readonly property int radiusPill: 100

  // ============ 图标尺寸 ============
  readonly property int iconSizeS: 14
  readonly property int iconSizeM: 18
  readonly property int iconSizeL: 22

  // ============ 动画时长（毫秒） ============
  readonly property int animFast: 120
  readonly property int animNormal: 200
  readonly property int animSlow: 300

  // ============ 字体族 ============
  // iconFont: 专用图标字体，「Symbols Nerd Font」只含 NF 图标字形，覆盖最全
  //   注意：不是「Symbols Nerd Font Mono」（未装，fontconfig 会回退到 Noto Sans）
  // monoFont: 等宽编程字体，同时内嵌 NF 图标（也可单独作为 iconFont 使用）
  readonly property string iconFont: "Symbols Nerd Font"
  readonly property string monoFont: "Maple Mono NF"

  /**
   * 给颜色叠加透明度
   * @param {color|string} c 颜色对象（如 Theme.primary / Qt.black）或十六进制字符串（如 "#ffffff" / "#fff"）
   * @param {number} a 透明度 0~1
   * @returns {color} 带 alpha 的颜色
   */
  function alpha(c, a) {
    if (typeof c === "string" && c.startsWith("#")) {
      const hex = c.slice(1)
      let r, g, b
      if (hex.length === 3) {
        r = parseInt(hex[0] + hex[0], 16) / 255
        g = parseInt(hex[1] + hex[1], 16) / 255
        b = parseInt(hex[2] + hex[2], 16) / 255
      } else {
        r = parseInt(hex.slice(0, 2), 16) / 255
        g = parseInt(hex.slice(2, 4), 16) / 255
        b = parseInt(hex.slice(4, 6), 16) / 255
      }
      return Qt.rgba(r, g, b, a)
    }
    return Qt.rgba(c.r, c.g, c.b, a)
  }
}
