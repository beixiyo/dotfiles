// Clipboard.qml — 剪贴板弹窗主组件（UI 组装）
//
// 只负责把通用原子组件（SearchBox / TagFilterBar / GlassPanel）与业务控制器
// （ClipboardController）组装成最终界面，并处理窗口定位、入场动画、快捷键与磨砂模糊。
// 所有数据与动作都委托给 clip，本文件保持精简。
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import QtQuick.Effects

import qs.Common
import qs.Common.components

Scope {
  id: root

  // ============ 业务控制器 ============
  ClipboardController {
    id: clip
    onCloseRequested: root.closeWithAnimation()
  }

  // ============ 动画状态 ============
  property real panelOpacity: 0
  property real panelScale: 0.95
  property real panelY: 15
  property bool blurActive: true

  // ============ UI 状态 ============
  property bool showTagFilters: false

  // ============ 窗口定位（来自环境变量） ============
  property string posEnv: Quickshell.env("QS_POS") || "center"
  property int marginT: Number.isFinite(parseInt(Quickshell.env("QS_MARGIN_T"))) ? parseInt(Quickshell.env("QS_MARGIN_T")) : 8
  property int marginR: Number.isFinite(parseInt(Quickshell.env("QS_MARGIN_R"))) ? parseInt(Quickshell.env("QS_MARGIN_R")) : 8
  property int marginB: Number.isFinite(parseInt(Quickshell.env("QS_MARGIN_B"))) ? parseInt(Quickshell.env("QS_MARGIN_B")) : 8
  property int marginL: Number.isFinite(parseInt(Quickshell.env("QS_MARGIN_L"))) ? parseInt(Quickshell.env("QS_MARGIN_L")) : 8
  property bool anchorTop: posEnv.indexOf("top") !== -1
  property bool anchorBottom: posEnv.indexOf("bottom") !== -1
  property bool anchorLeft: posEnv.indexOf("left") !== -1
  property bool anchorRight: posEnv.indexOf("right") !== -1
  property bool anchorVCenter: posEnv === "center-left" || posEnv === "center" || posEnv === "center-right"
  property bool anchorHCenter: posEnv === "top-center" || posEnv === "center" || posEnv === "bottom-center"

  /** 关闭窗口：停止后台工作、淡出并退出进程 */
  function closeWithAnimation() {
    if (clip.closing)
      return
    clip.beginClose()
    root.blurActive = false
    root.panelOpacity = 0
    Qt.quit()
  }

  Component.onCompleted: enterAnimation.start()

  // ============ 入 / 出场动画 ============
  ParallelAnimation {
    id: enterAnimation
    NumberAnimation {
      target: root
      property: "panelOpacity"
      from: 0
      to: 1
      duration: 20
    }
    NumberAnimation {
      target: root
      property: "panelScale"
      from: 0.98
      to: 1.0
      duration: 20
    }
    NumberAnimation {
      target: root
      property: "panelY"
      from: 4
      to: 0
      duration: 20
    }
  }

  ParallelAnimation {
    id: exitAnimation
    NumberAnimation {
      target: root
      property: "panelOpacity"
      to: 0
      duration: 20
    }
    NumberAnimation {
      target: root
      property: "panelScale"
      to: 0.98
      duration: 20
    }
    NumberAnimation {
      target: root
      property: "panelY"
      to: -4
      duration: 20
    }
    onFinished: Qt.quit()
  }

  // ============ 窗口 ============
  Variants {
    model: ScreenModel.targetScreens(Quickshell.screens, Quickshell.env("QS_TARGET_OUTPUT"))

    PanelWindow {
      id: panel
      required property ShellScreen modelData
      screen: modelData
      // 通过属性持有控制器：Variants 委托内对 clip 做 id 直引用的绑定不具响应性，
      // 改为属性链 ctl.xxx 即可正常追踪控制器属性变化
      property var ctl: clip

      color: "transparent"
      WlrLayershell.namespace: "quickshell-clipboard"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
      BackgroundEffect.blurRegion: Region {
        id: blurRegion
        item: root.blurActive ? mainContainer : null
        radius: Theme.radiusXL + 4
      }
      Connections {
        target: root
        function onBlurActiveChanged() {
          blurRegion.changed()
        }
        function onPanelScaleChanged() {
          blurRegion.changed()
        }
        function onPanelYChanged() {
          blurRegion.changed()
        }
      }
      Connections {
        target: mainContainer
        function onXChanged() {
          blurRegion.changed()
        }
        function onYChanged() {
          blurRegion.changed()
        }
        function onWidthChanged() {
          blurRegion.changed()
        }
        function onHeightChanged() {
          blurRegion.changed()
        }
      }
      anchors.top: true
      anchors.bottom: true
      anchors.left: true
      anchors.right: true

      Shortcut {
        sequence: "Escape"
        onActivated: panel.ctl.previewVisible ? panel.ctl.hidePreview() : root.closeWithAnimation()
      }
      Shortcut {
        sequence: "Return"
        onActivated: panel.ctl.selectCurrent()
      }
      Shortcut {
        sequence: "Enter"
        onActivated: panel.ctl.selectCurrent()
      }
      Shortcut {
        sequence: "Up"
        onActivated: {
          if (panel.ctl.selectedIndex > 0)
            panel.ctl.selectedIndex--
        }
      }
      Shortcut {
        sequence: "Down"
        onActivated: {
          if (panel.ctl.selectedIndex < panel.ctl.filteredItems.length - 1)
            panel.ctl.selectedIndex++
        }
      }
      // Vim 风格：Ctrl+N 下移、Ctrl+P 上移（方向键同样可用）
      Shortcut {
        sequence: "Ctrl+N"
        onActivated: panel.ctl.selectedIndex < panel.ctl.filteredItems.length - 1 ? panel.ctl.selectedIndex++ : null
      }
      Shortcut {
        sequence: "Ctrl+P"
        onActivated: panel.ctl.selectedIndex > 0 ? panel.ctl.selectedIndex-- : null
      }
      // 预览选中条目（Alt+P）
      Shortcut {
        sequence: "Alt+P"
        onActivated: panel.ctl.filteredItems.length > 0 ? panel.ctl.showPreview(panel.ctl.filteredItems[panel.ctl.selectedIndex]) : null
      }

      MouseArea {
        anchors.fill: parent
        onClicked: root.closeWithAnimation()
      }

      // 主面板（玻璃）
      GlassPanel {
        id: mainContainer
        anchors.top: root.anchorTop ? parent.top : undefined
        anchors.bottom: root.anchorBottom ? parent.bottom : undefined
        anchors.left: root.anchorLeft ? parent.left : undefined
        anchors.right: root.anchorRight ? parent.right : undefined
        anchors.horizontalCenter: root.anchorHCenter ? parent.horizontalCenter : undefined
        anchors.verticalCenter: root.anchorVCenter ? parent.verticalCenter : undefined
        anchors.topMargin: root.anchorTop ? root.marginT : 0
        anchors.bottomMargin: root.anchorBottom ? root.marginB : 0
        anchors.leftMargin: root.anchorLeft ? root.marginL : 0
        anchors.rightMargin: root.anchorRight ? root.marginR : 0
        width: 650
        height: 550
        fillColor: Theme.alpha(Theme.background, 0.7)
        cornerRadius: Theme.radiusXL + 4

        // BackgroundEffect 依据 item 几何，故不要对绑定模糊的 item 做 transform
        opacity: root.panelOpacity

        MouseArea {
          anchors.fill: parent
          onClicked: function (mouse) {
            mouse.accepted = true
          }
        }

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Theme.spacingXL
          spacing: Theme.spacingL

          // 搜索 + 清空
          RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingS

            SearchBox {
              Layout.fillWidth: true
              Layout.preferredHeight: 40
              filterActive: root.showTagFilters
              onTextEdited: panel.ctl.searchText = text
              onFilterToggled: root.showTagFilters = !root.showTagFilters
            }

            // 清空全部（二次确认，避免误触）
            Rectangle {
              id: clearBtn
              property bool confirming: false
              Layout.preferredHeight: 40
              Layout.preferredWidth: confirming ? (clearRow.implicitWidth + Theme.spacingL * 2) : 40
              radius: Theme.radiusL
              color: confirming ? Theme.alpha(Theme.error, 0.15) : (clearHover.hovered ? Theme.surfaceVariant : Theme.surface)
              border.color: confirming ? Theme.error : (clearHover.hovered ? Theme.alpha(Theme.error, 0.6) : Theme.outline)
              border.width: 0.5

              Behavior on Layout.preferredWidth {
                NumberAnimation {
                  duration: Theme.animFast
                }
              }

              Row {
                id: clearRow
                anchors.centerIn: parent
                spacing: 4

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "\uf1f8"
                  font.family: Theme.iconFont
                  font.pixelSize: 15
                  color: (clearBtn.confirming || clearHover.hovered) ? Theme.error : Theme.textSecondary
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  visible: clearBtn.confirming
                  text: "确认清空?"
                  font.pixelSize: Theme.fontSizeXS
                  color: Theme.error
                }
              }

              HoverHandler {
                id: clearHover
              }
              TapHandler {
                onTapped: {
                  if (clearBtn.confirming) {
                    panel.ctl.clearAll()
                    clearBtn.confirming = false
                  } else {
                    clearBtn.confirming = true
                    clearConfirmTimer.restart()
                  }
                }
              }
              Timer {
                id: clearConfirmTimer
                interval: 3000
                onTriggered: clearBtn.confirming = false
              }
            }
          }

          // 标签过滤
          TagFilterBar {
            visible: root.showTagFilters || panel.ctl.activeTagFilters.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? 30 : 0
            options: panel.ctl.tagFilterOptions
            activeTags: panel.ctl.activeTagFilters
            counts: panel.ctl.tagCounts
            onTagToggled: tag => panel.ctl.toggleTagFilter(tag)
            onCleared: panel.ctl.clearTagFilters()
          }

          // 列表
          Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // 空态
            ColumnLayout {
              visible: panel.ctl.filteredItems.length === 0 && !panel.ctl.loading
              anchors.centerIn: parent
              spacing: Theme.spacingM

              Text {
                Layout.alignment: Qt.AlignHCenter
                text: "\uf0ea"
                font.family: Theme.iconFont
                font.pixelSize: 48
                color: Theme.outline
              }

              Text {
                Layout.alignment: Qt.AlignHCenter
                text: (panel.ctl.searchText || panel.ctl.activeTagFilters.length > 0) ? "没有匹配" : "剪贴板为空"
                font.pixelSize: Theme.fontSizeM
                color: Theme.textMuted
              }
            }

            // 加载中
            Text {
              visible: panel.ctl.loading && panel.ctl.filteredItems.length === 0
              anchors.centerIn: parent
              text: panel.ctl.parsing ? "解析中..." : "加载中..."
              font.pixelSize: Theme.fontSizeM
              color: Theme.textMuted
            }

            ListView {
              id: listFlickable
              anchors.fill: parent
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              spacing: Theme.spacingS
              model: panel.ctl.filteredItems
              cacheBuffer: Math.max(1800, height * 4)
              reuseItems: true
              readonly property int scrollbarGutter: 31
              readonly property int scrollbarWidth: 6
              readonly property int itemLeftInset: 12

              ScrollBar.vertical: ScrollBar {
                id: listScrollbar
                width: listFlickable.scrollbarWidth
                x: listFlickable.width - ((listFlickable.scrollbarGutter + width) / 2)
                policy: ScrollBar.AsNeeded
                minimumSize: Math.min(1, 30 / Math.max(1, listFlickable.height))

                contentItem: Rectangle {
                  implicitWidth: 6
                  implicitHeight: 30
                  radius: 3
                  color: listScrollbar.pressed || listScrollbar.hovered ? Theme.textMuted : Theme.alpha(Theme.textMuted, 0.4)

                  Behavior on color {
                    ColorAnimation {
                      duration: Theme.animFast
                    }
                  }
                }
              }

              Connections {
                target: panel.ctl
                function onSelectedIndexChanged() {
                  if (panel.ctl.selectedIndex >= 0 && panel.ctl.selectedIndex < listFlickable.count)
                    listFlickable.positionViewAtIndex(panel.ctl.selectedIndex, ListView.Contain)
                }
              }

              delegate: ClipDelegate {
                controller: panel.ctl
                selectedIndex: panel.ctl.selectedIndex
                listView: listFlickable
              }
            }
          }
        }
      }

      // 预览层
      PreviewOverlay {
        anchors.fill: parent
        controller: panel.ctl
      }
    }
  }
}
