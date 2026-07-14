// ClipDelegate.qml — 剪贴板列表单项卡片
//
// 渲染一条剪贴板记录：左侧类型小图标、可选的可视缩略图（图片/GIF/视频/HTML 内嵌图）、
// 颜色色块、内容预览与文件路径、删除按钮。完全由 modelData 驱动，动作通过注入的
// controller 回调完成。
import QtQuick
import QtQuick.Layouts

import qs.Common
import "ClipboardLogic.js" as Logic

Item {
  id: clipDelegate

  required property var modelData
  required property int index

  /** 业务控制器（由 ListView 注入） */
  property var controller
  /** 当前高亮的条目索引 */
  property int selectedIndex: -1
  /** 所属 ListView（用于读取宽度、滚动条让位等几何信息） */
  property var listView: null

  readonly property var badge: controller ? controller.typeBadgeInfo(modelData) : ({ label: "", icon: "", color: Theme.textMuted })
  readonly property bool hasVisualPreview: !!modelData.hasVisualPreview
  readonly property bool hasScrollbar: listView ? listView.contentHeight > listView.height : false

  width: listView ? listView.width : 0
  height: hasVisualPreview ? 80 : 56

  Rectangle {
    id: clipItem

    readonly property var modelData: clipDelegate.modelData
    readonly property int index: clipDelegate.index
    readonly property var badge: clipDelegate.badge
    readonly property bool hasVisualPreview: clipDelegate.hasVisualPreview

    x: clipDelegate.hasScrollbar ? (clipDelegate.listView ? clipDelegate.listView.itemLeftInset : 0) : 0
    width: (clipDelegate.listView ? clipDelegate.listView.width : 0) - (clipDelegate.hasScrollbar ? (clipDelegate.listView ? clipDelegate.listView.scrollbarGutter : 0) : 0)
    height: parent.height
    radius: Theme.radiusM
    color: index === clipDelegate.selectedIndex ? Theme.alpha(Theme.primary, 0.1) : (itemHover.hovered ? Theme.surfaceVariant : Theme.surface)
    border.color: index === clipDelegate.selectedIndex ? Theme.primary : Theme.outline
    border.width: 0.5

    Behavior on color {
      ColorAnimation {
        duration: Theme.animFast
      }
    }
    Behavior on border.color {
      ColorAnimation {
        duration: Theme.animFast
      }
    }

    HoverHandler {
      id: itemHover
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onClicked: function (mouse) {
        if (mouse.button === Qt.RightButton) {
          clipDelegate.controller.showPreview(clipItem.modelData)
        } else {
          clipDelegate.controller.selectItem(clipItem.modelData)
        }
      }
    }

    RowLayout {
      anchors.fill: parent
      anchors.margins: Theme.spacingM
      spacing: Theme.spacingM

      // 类型小图标
      Rectangle {
        Layout.preferredWidth: 28
        Layout.preferredHeight: 28
        Layout.alignment: Qt.AlignVCenter
        radius: Theme.radiusS
        color: Theme.alpha(clipItem.badge.color, 0.1)

        Text {
          anchors.centerIn: parent
          text: clipItem.badge.icon
          font.family: Theme.iconFont
          font.pixelSize: 14
          color: clipItem.badge.color
        }
      }

      // 可视缩略图（按需显示）
      Rectangle {
        visible: clipItem.hasVisualPreview
        Layout.preferredWidth: 56
        Layout.preferredHeight: 56
        Layout.alignment: Qt.AlignVCenter
        radius: Theme.radiusS
        color: Theme.surfaceVariant
        clip: true

        // 二进制图片（cliphist decode 出来的）
        AnimatedImage {
          id: previewBinaryImg
          anchors.fill: parent
          anchors.margins: 2
          visible: clipItem.modelData.isImage
          source: (clipItem.modelData.isImage && clipDelegate.controller.imagePaths[clipItem.modelData.id]) ? "file://" + clipDelegate.controller.imagePaths[clipItem.modelData.id] : ""
          fillMode: Image.PreserveAspectCrop
          playing: true
          asynchronous: true
        }

        // 文件图片（静态）
        Image {
          id: previewFileImg
          anchors.fill: parent
          anchors.margins: 2
          visible: clipItem.modelData.isFile && clipItem.modelData.fileType === "image"
          source: (clipItem.modelData.isFile && clipItem.modelData.fileType === "image" && clipItem.modelData.filePaths.length > 0) ? "file://" + clipItem.modelData.filePaths[0] : ""
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
        }

        // 文件 GIF（动图）
        AnimatedImage {
          id: previewFileGif
          anchors.fill: parent
          anchors.margins: 2
          visible: clipItem.modelData.isFile && clipItem.modelData.fileType === "gif"
          source: (clipItem.modelData.isFile && clipItem.modelData.fileType === "gif" && clipItem.modelData.filePaths.length > 0) ? "file://" + clipItem.modelData.filePaths[0] : ""
          fillMode: Image.PreserveAspectCrop
          playing: true
          asynchronous: true
        }

        // 文件视频缩略图
        Image {
          id: previewVideoThumb
          anchors.fill: parent
          anchors.margins: 2
          visible: clipItem.modelData.isFile && clipItem.modelData.fileType === "video"
          source: {
            if (!clipItem.modelData.isFile || clipItem.modelData.fileType !== "video" || clipItem.modelData.filePaths.length === 0)
              return ""
            var path = Logic.normalizeLocalPath(clipItem.modelData.filePaths[0])
            var thumb = path ? clipDelegate.controller.videoThumbPaths[path] : ""
            return thumb ? "file://" + thumb : ""
          }
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          onStatusChanged: {
            if (status === Image.Error && clipItem.modelData.filePaths.length > 0) {
              clipDelegate.controller.removeVideoThumbPath(clipItem.modelData.filePaths[0])
            }
          }
        }

        // HTML 内嵌图片
        AnimatedImage {
          id: previewHtmlImg
          anchors.fill: parent
          anchors.margins: 2
          visible: clipItem.modelData.textType === "html" && clipItem.modelData.htmlImageSrcs && clipItem.modelData.htmlImageSrcs.length > 0 && clipDelegate.controller.isLocalImagePath(clipItem.modelData.htmlImageSrcs[0])
          source: (clipItem.modelData.textType === "html" && clipItem.modelData.htmlImageSrcs && clipItem.modelData.htmlImageSrcs.length > 0 && clipDelegate.controller.isLocalImagePath(clipItem.modelData.htmlImageSrcs[0])) ? Logic.localFileUrl(clipItem.modelData.htmlImageSrcs[0]) : ""
          fillMode: Image.PreserveAspectCrop
          playing: true
          asynchronous: true
        }

        // 无图可加载时的兜底图标
        Text {
          visible: clipItem.hasVisualPreview && previewBinaryImg.status !== Image.Ready && previewFileImg.status !== Image.Ready && previewFileGif.status !== Image.Ready && previewVideoThumb.status !== Image.Ready && previewHtmlImg.status !== Image.Ready
          anchors.centerIn: parent
          text: "\uf03e"
          font.family: Theme.iconFont
          font.pixelSize: 20
          color: Theme.textMuted
        }

        // 视频播放角标
        Rectangle {
          visible: clipItem.modelData.isFile && clipItem.modelData.fileType === "video" && previewVideoThumb.status === Image.Ready
          anchors.centerIn: parent
          width: 20
          height: 20
          radius: 10
          color: Theme.alpha(Qt.black, 0.5)

          Text {
            anchors.centerIn: parent
            text: "\uf04b"
            font.family: Theme.iconFont
            font.pixelSize: 8
            color: "white"
          }
        }

        // GIF 角标
        Rectangle {
          visible: (clipItem.modelData.isFile && clipItem.modelData.fileType === "gif") || (clipItem.modelData.isImage && clipItem.modelData.preview.toLowerCase().indexOf("gif") >= 0)
          anchors.bottom: parent.bottom
          anchors.right: parent.right
          anchors.margins: 3
          width: gifOvLabel.implicitWidth + 6
          height: gifOvLabel.implicitHeight + 3
          radius: 3
          color: Theme.alpha(Qt.black, 0.6)

          Text {
            id: gifOvLabel
            anchors.centerIn: parent
            text: "GIF"
            font.pixelSize: 8
            font.bold: true
            color: "white"
          }
        }

        // HTML 角标
        Rectangle {
          visible: clipItem.modelData.textType === "html" && previewHtmlImg.visible
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.margins: 3
          width: htmlOvLabel.implicitWidth + 6
          height: htmlOvLabel.implicitHeight + 3
          radius: 3
          color: Theme.alpha(Qt.black, 0.6)

          Text {
            id: htmlOvLabel
            anchors.centerIn: parent
            text: "HTML"
            font.pixelSize: 7
            font.bold: true
            color: "white"
          }
        }
      }

      // 颜色色块（仅颜色类型）
      Rectangle {
        visible: !clipItem.modelData.isImage && !clipItem.modelData.isFile && clipItem.modelData.textType === "color"
        Layout.preferredWidth: 28
        Layout.preferredHeight: 28
        Layout.alignment: Qt.AlignVCenter
        radius: Theme.radiusS
        color: clipItem.modelData.colorValue || "transparent"
        border.color: Theme.outline
        border.width: 0.5
      }

      // 内容信息
      ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        Layout.fillHeight: true
        spacing: 2

        Text {
          Layout.fillWidth: true
          text: clipItem.modelData.preview
          font.pixelSize: Theme.fontSizeM
          color: clipItem.modelData.isImage ? Theme.textSecondary : Theme.textPrimary
          elide: clipItem.modelData.isFile ? Text.ElideMiddle : Text.ElideRight
          maximumLineCount: 1
        }

        // 文件路径信息
        Text {
          visible: clipItem.modelData.isFile && clipItem.modelData.filePaths.length > 0
          Layout.fillWidth: true
          text: {
            if (!clipItem.modelData.isFile || clipItem.modelData.filePaths.length === 0)
              return ""
            var p = clipItem.modelData.filePaths[0]
            var dir = p.substring(0, p.lastIndexOf("/"))
            var suffix = clipItem.modelData.filePaths.length > 1 ? "  (+" + (clipItem.modelData.filePaths.length - 1) + " 文件)" : ""
            return dir + suffix
          }
          font.pixelSize: Theme.fontSizeXS
          color: Theme.textMuted
          elide: Text.ElideMiddle
          maximumLineCount: 1
        }
      }

      // 置顶按钮（置顶项常驻高亮，普通项悬停显示）
      Rectangle {
        readonly property bool pinned: !!clipItem.modelData.pinned
        width: 24
        height: 24
        radius: 12
        Layout.alignment: Qt.AlignVCenter
        color: pinHover.hovered ? Theme.alpha(Theme.primary, 0.2) : "transparent"
        visible: pinned || itemHover.hovered || pinHover.hovered

        Text {
          anchors.centerIn: parent
          text: "\uf08d"
          font.family: Theme.iconFont
          font.pixelSize: 12
          color: (parent.pinned || pinHover.hovered) ? Theme.primary : Theme.textSecondary
        }

        HoverHandler {
          id: pinHover
        }
        TapHandler {
          onTapped: clipDelegate.controller.togglePin(clipItem.modelData)
        }
      }

      // 删除按钮（置顶项不显示删除，用取消置顶代替）
      Rectangle {
        width: 24
        height: 24
        radius: 12
        Layout.alignment: Qt.AlignVCenter
        color: delHover.hovered ? Theme.alpha(Theme.error, 0.2) : "transparent"
        visible: !clipItem.modelData.pinned && (itemHover.hovered || delHover.hovered)

        Text {
          anchors.centerIn: parent
          text: "\uf00d"
          font.family: Theme.iconFont
          font.pixelSize: 12
          color: delHover.hovered ? Theme.error : Theme.textSecondary
        }

        HoverHandler {
          id: delHover
        }
        TapHandler {
          onTapped: clipDelegate.controller.deleteItem(clipItem.modelData)
        }
      }
    }
  }
}
