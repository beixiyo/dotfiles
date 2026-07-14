// GlassPanel.qml — 玻璃拟态面板（通用原子组件）
//
// 统一封装「半透明填充 + 0.5px 极细外描边 + 柔和落影 + 玻璃内描边」这套视觉，
// 主窗口与预览窗共用，避免重复。本身是一个 Rectangle，调用方可直接设置
// anchors / width / height / opacity 等几何属性，子元素写在标签内即作为内容。
//
// 用法：
//   GlassPanel {
//     width: 650; height: 550
//     ColumnLayout { anchors.fill: parent; anchors.margins: Theme.spacingXL; ... }
//   }
import QtQuick
import QtQuick.Effects

import qs.Common

Rectangle {
  id: glass

  /** 内容（默认属性）：写在 GlassPanel 标签内的子元素会铺满面板 */
  default property alias content: contentHolder.data

  /** 面板填充色（含透明度） */
  property color fillColor: Theme.alpha(Theme.background, 0.7)
  /** 圆角半径 */
  property real cornerRadius: Theme.radiusXL + 4
  /** 外描边颜色 */
  property color frameColor: Theme.glassBorder
  /** 落影模糊度 */
  property real panelShadowBlur: 0.5
  /** 落影垂直偏移 */
  property real panelShadowOffset: 8

  color: fillColor
  radius: cornerRadius
  border.color: frameColor
  border.width: 0.5

  // 柔和落影
  layer.enabled: true
  layer.effect: MultiEffect {
    shadowEnabled: true
    shadowColor: Theme.shadowColor
    shadowBlur: glass.panelShadowBlur
    shadowVerticalOffset: glass.panelShadowOffset
  }

  // 内容容器
  Item {
    id: contentHolder
    anchors.fill: parent
  }

  // 玻璃内描边（叠在内容之上，仅一条极细高光线）
  Rectangle {
    anchors.fill: parent
    radius: parent.radius
    color: "transparent"
    border.width: 0.5
    border.color: Theme.glassHighlight
    z: 10
  }
}
