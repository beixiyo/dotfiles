// TagFilterBar.qml — 标签过滤条（通用原子组件）
//
// 横向可滚动的标签筛选条：根据传入的选项与计数渲染一排可点选的标签胶囊，
// 末尾附带「清除」按钮。纯展示 + 回调，不持有任何过滤状态。
//
// 用法：
//   TagFilterBar {
//     Layout.fillWidth: true
//     options: controller.tagFilterOptions
//     activeTags: controller.activeTagFilters
//     counts: controller.tagCounts
//     onTagToggled: controller.toggleTagFilter(tag)
//     onCleared: controller.clearTagFilters()
//   }
import QtQuick

import qs.Common

Flickable {
  id: bar

  /** 标签选项列表，每项形如 { id, label, icon } */
  property var options: []
  /** 当前已激活的标签 id 数组 */
  property var activeTags: []
  /** 各标签的计数映射 { tagId: number } */
  property var counts: ({})

  /** 某个标签被点选时触发 */
  signal tagToggled(string tag)
  /** 清除按钮被点击时触发 */
  signal cleared

  contentWidth: tagFilterRow.implicitWidth
  contentHeight: height
  clip: true
  interactive: contentWidth > width
  boundsBehavior: Flickable.StopAtBounds

  Row {
    id: tagFilterRow
    anchors.verticalCenter: parent.verticalCenter
    spacing: Theme.spacingS

    Repeater {
      model: bar.options

      Rectangle {
        id: chip
        required property var modelData

        readonly property string tagId: modelData.id
        readonly property bool active: bar.activeTags.indexOf(tagId) !== -1
        readonly property int count: bar.counts[tagId] || 0

        visible: count > 0 || active
        height: 28
        width: tagChipContent.implicitWidth + Theme.spacingM * 2
        radius: 14
        color: active ? Theme.alpha(Theme.primary, 0.14) : Theme.surface
        border.color: active ? Theme.primary : Theme.outline
        border.width: 0.5

        Row {
          id: tagChipContent
          anchors.centerIn: parent
          spacing: 4

          Text {
            text: chip.modelData.icon || ""
            font.family: Theme.iconFont
            font.pixelSize: 10
            color: chip.active ? Theme.primary : Theme.textSecondary
          }

          Text {
            text: chip.modelData.label + " " + chip.count
            font.pixelSize: Theme.fontSizeXS
            color: chip.active ? Theme.primary : Theme.textSecondary
          }
        }

        TapHandler {
          onTapped: bar.tagToggled(chip.tagId)
        }
      }
    }

    // 清除标签按钮
    Rectangle {
      visible: bar.activeTags.length > 0
      height: 28
      width: clearTagLabel.implicitWidth + Theme.spacingM * 2
      radius: 14
      color: Theme.alpha(Theme.error, 0.1)
      border.color: Theme.error
      border.width: 0.5

      Text {
        id: clearTagLabel
        anchors.centerIn: parent
        text: "清除标签"
        font.pixelSize: Theme.fontSizeXS
        color: Theme.error
      }

      TapHandler {
        onTapped: bar.cleared()
      }
    }
  }
}
