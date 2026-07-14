// SearchBox.qml — 搜索过滤条（通用原子组件）
//
// 完全 props 驱动、signal 回调、无业务耦合：自身只负责「输入框 + 搜索图标 +
// 过滤切换按钮」的渲染与交互，不关心搜索结果如何处理。
//
// 用法：
//   SearchBox {
//     Layout.fillWidth: true
//     filterActive: showFilters
//     onTextEdited: controller.searchText = text
//     onFilterToggled: showFilters = !showFilters
//   }
import QtQuick

import qs.Common

Rectangle {
  id: box

  /** 当前输入文本（可双向绑定 / 读取） */
  property alias text: input.text
  /** 占位提示文字 */
  property string placeholder: "搜索..."
  /** 过滤按钮是否处于激活态（由调用方控制） */
  property bool filterActive: false
  /** 是否显示右侧过滤切换按钮 */
  property bool showFilterButton: true

  /** 文本被用户编辑时触发（仅用户输入，不含程序赋值） */
  signal textEdited(string text)
  /** 过滤按钮被点击时触发 */
  signal filterToggled

  /** 让输入框获得焦点 */
  function focusInput() {
    input.forceActiveFocus()
  }

  implicitHeight: 40
  radius: Theme.radiusL
  color: Theme.surface
  border.color: input.activeFocus ? Theme.primary : Theme.outline
  border.width: 0.5

  Text {
    id: searchIcon
    anchors.left: parent.left
    anchors.leftMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    text: ""
    font.family: Theme.iconFont
    font.pixelSize: 14
    color: Theme.textMuted
  }

  TextInput {
    id: input
    anchors.left: searchIcon.right
    anchors.leftMargin: 8
    anchors.right: box.showFilterButton ? funnelButton.left : parent.right
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    font.pixelSize: Theme.fontSizeM
    color: Theme.textPrimary
    clip: true
    focus: true
    verticalAlignment: TextInput.AlignVCenter
    onTextChanged: box.textEdited(text)

    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: box.placeholder
      font.pixelSize: Theme.fontSizeM
      color: Theme.textMuted
      visible: !input.text
    }
  }

  // 过滤切换按钮（漏斗）
  Rectangle {
    id: funnelButton
    visible: box.showFilterButton
    width: 28
    height: 28
    anchors.right: parent.right
    anchors.rightMargin: 6
    anchors.verticalCenter: parent.verticalCenter
    radius: Theme.radiusM
    color: box.filterActive ? Theme.alpha(Theme.primary, 0.14) : (tagToggleHover.hovered ? Theme.surfaceVariant : "transparent")
    border.color: box.filterActive ? Theme.primary : "transparent"
    border.width: box.filterActive ? 0.5 : 0

    Text {
      anchors.centerIn: parent
      text: ""
      font.family: Theme.iconFont
      font.pixelSize: 13
      color: box.filterActive ? Theme.primary : Theme.textMuted
    }

    HoverHandler {
      id: tagToggleHover
    }
    TapHandler {
      onTapped: box.filterToggled()
    }
  }
}
