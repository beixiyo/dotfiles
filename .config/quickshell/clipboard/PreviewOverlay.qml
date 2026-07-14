// PreviewOverlay.qml — 全屏媒体 / 文本详情预览层
//
// 覆盖在主窗口之上的半透明遮罩 + 居中详情面板。自适应放大到几乎全屏（四边留白 40px），
// 支持图片 / GIF / 视频（缩略图 + 元数据 + 打开）/ 多文件列表 / 纯文本的预览。
// 数据与动作均来自注入的 controller。
import QtQuick
import QtQuick.Layouts

import qs.Common
import qs.Common.components
import "ClipboardLogic.js" as Logic

Rectangle {
  id: overlay

  /** 业务控制器 */
  property var controller

  visible: controller && controller.previewVisible
  anchors.fill: parent
  color: Theme.alpha(Qt.black, 0.5)

  MouseArea {
    anchors.fill: parent
    onClicked: overlay.controller.hidePreview()
  }

  GlassPanel {
    anchors.centerIn: parent
    width: parent.width - 80
    height: parent.height - 80
    fillColor: Theme.alpha(Theme.background, 0.92)
    cornerRadius: Theme.radiusXL + 2

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

      // 预览头部
      RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingM

        Text {
          text: {
            var item = overlay.controller.previewItem
            if (!item)
              return "\uf0f6"
            if (item.isImage)
              return "\uf03e"
            if (item.isFile) {
              if (item.filePaths.length > 1)
                return "\uf0c5"
              if (item.fileType === "gif")
                return "\uf03e"
              if (item.fileType === "image")
                return "\uf03e"
              if (item.fileType === "video")
                return "\uf03d"
              return "\uf15b"
            }
            return "\uf0f6"
          }
          font.family: Theme.iconFont
          font.pixelSize: 18
          color: Theme.primary
        }

        Text {
          text: {
            var item = overlay.controller.previewItem
            if (!item)
              return ""
            if (item.isImage)
              return "图片预览"
            if (item.isFile) {
              if (item.filePaths.length > 1)
                return "文件列表"
              if (item.fileType === "gif")
                return "GIF 预览"
              if (item.fileType === "image")
                return "图片预览"
              if (item.fileType === "video")
                return "视频预览"
              return "文件信息"
            }
            return "文本预览"
          }
          font.pixelSize: Theme.fontSizeL
          font.bold: true
          color: Theme.textPrimary
        }

        // 头部图片元信息
        Text {
          visible: overlay.controller.previewItem && overlay.controller.previewItem.isImage && overlay.controller.previewItem.imageDimensions
          text: overlay.controller.previewItem ? (overlay.controller.previewItem.imageDimensions || "") + (overlay.controller.previewItem.imageSize ? " | " + overlay.controller.previewItem.imageSize : "") : ""
          font.pixelSize: Theme.fontSizeXS
          color: Theme.textMuted
        }

        Item {
          Layout.fillWidth: true
        }

        // 打开视频按钮
        Rectangle {
          visible: overlay.controller.previewVideoPath().length > 0
          width: openVideoLabel.implicitWidth + Theme.spacingM * 2
          height: 28
          radius: Theme.radiusM
          color: openVideoHover.hovered ? Theme.surfaceVariant : Theme.alpha(Theme.primary, 0.08)
          border.color: Theme.alpha(Theme.primary, openVideoHover.hovered ? 0.65 : 0.35)
          border.width: 0.5

          Text {
            id: openVideoLabel
            anchors.centerIn: parent
            text: "打开视频"
            font.pixelSize: Theme.fontSizeXS
            font.bold: true
            color: Theme.primary
          }

          HoverHandler {
            id: openVideoHover
          }
          TapHandler {
            onTapped: overlay.controller.openPreviewVideo()
          }
        }

        Text {
          visible: overlay.controller.previewItem && overlay.controller.previewItem.isImage && overlay.controller.saveImageStatus
          Layout.maximumWidth: 220
          text: overlay.controller.saveImageStatus
          font.pixelSize: Theme.fontSizeXS
          color: overlay.controller.saveImageStatus === "保存失败" ? Theme.error : Theme.textMuted
          elide: Text.ElideMiddle
          maximumLineCount: 1
        }

        // 保存图片按钮
        Rectangle {
          visible: overlay.controller.previewItem && overlay.controller.previewItem.isImage
          width: saveImageLabel.implicitWidth + Theme.spacingM * 2
          height: 28
          radius: Theme.radiusM
          color: saveImageHover.hovered ? Theme.surfaceVariant : Theme.alpha(Theme.primary, 0.08)
          border.color: Theme.alpha(Theme.primary, saveImageHover.hovered ? 0.65 : 0.35)
          border.width: 0.5

          Text {
            id: saveImageLabel
            anchors.centerIn: parent
            text: overlay.controller.saveImageRunning ? "保存中" : "保存图片"
            font.pixelSize: Theme.fontSizeXS
            font.bold: true
            color: Theme.primary
          }

          HoverHandler {
            id: saveImageHover
          }
          TapHandler {
            onTapped: overlay.controller.savePreviewImageToDisk()
          }
        }

        // 关闭按钮
        Rectangle {
          width: 28
          height: 28
          radius: Theme.radiusM
          color: previewCloseHover.hovered ? Theme.surfaceVariant : "transparent"

          Text {
            anchors.centerIn: parent
            text: "\uf00d"
            font.family: Theme.iconFont
            font.pixelSize: 16
            color: Theme.textSecondary
          }

          HoverHandler {
            id: previewCloseHover
          }
          TapHandler {
            onTapped: overlay.controller.hidePreview()
          }
        }
      }

      Rectangle {
        Layout.fillWidth: true
        height: 1
        color: Theme.outline
        opacity: 0.6
      }

      // 预览内容
      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        Flickable {
          id: previewFlickable
          anchors.fill: parent
          contentWidth: width
          contentHeight: {
            var item = overlay.controller.previewItem
            if (!item)
              return 0
            if (item.isImage)
              return previewImage.height
            if (item.isFile) {
              if (item.filePaths.length > 1)
                return previewFileInfo.implicitHeight
              if (item.fileType === "gif")
                return previewGif.height
              if (item.fileType === "image")
                return previewFileImage.height
              if (item.fileType === "video")
                return previewVideoPanel.implicitHeight
              return previewFileInfo.implicitHeight
            }
            if (item.textType === "html" && item.htmlImageSrcs && item.htmlImageSrcs.length > 0 && overlay.controller.isLocalImagePath(item.htmlImageSrcs[0]))
              return previewHtmlImage.height
            return previewTextEdit.contentHeight
          }
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          // 二进制图片预览
          AnimatedImage {
            id: previewImage
            visible: overlay.controller.previewItem && overlay.controller.previewItem.isImage
            width: parent.width
            source: overlay.controller.previewItem && overlay.controller.previewItem.isImage && overlay.controller.imagePaths[overlay.controller.previewItem.id] ? "file://" + overlay.controller.imagePaths[overlay.controller.previewItem.id] : ""
            fillMode: Image.PreserveAspectFit
            playing: true
            asynchronous: true
          }

          // 文件图片预览
          Image {
            id: previewFileImage
            visible: overlay.controller.previewItem && overlay.controller.previewItem.isFile && overlay.controller.previewItem.filePaths.length <= 1 && overlay.controller.previewItem.fileType === "image"
            width: parent.width
            source: (overlay.controller.previewItem && overlay.controller.previewItem.isFile && overlay.controller.previewItem.filePaths.length <= 1 && overlay.controller.previewItem.fileType === "image" && overlay.controller.previewItem.filePaths.length > 0) ? "file://" + overlay.controller.previewItem.filePaths[0] : ""
            fillMode: Image.PreserveAspectFit
            asynchronous: true
          }

          // GIF 预览
          AnimatedImage {
            id: previewGif
            visible: overlay.controller.previewItem && overlay.controller.previewItem.isFile && overlay.controller.previewItem.filePaths.length <= 1 && overlay.controller.previewItem.fileType === "gif"
            width: parent.width
            source: (overlay.controller.previewItem && overlay.controller.previewItem.isFile && overlay.controller.previewItem.filePaths.length <= 1 && overlay.controller.previewItem.fileType === "gif" && overlay.controller.previewItem.filePaths.length > 0) ? "file://" + overlay.controller.previewItem.filePaths[0] : ""
            fillMode: Image.PreserveAspectFit
            playing: true
            asynchronous: true
          }

          // 视频缩略图 + 元数据
          ColumnLayout {
            id: previewVideoPanel
            visible: overlay.controller.previewItem && overlay.controller.previewItem.isFile && overlay.controller.previewItem.filePaths.length <= 1 && overlay.controller.previewItem.fileType === "video"
            width: parent.width
            spacing: Theme.spacingM
            property string videoPath: overlay.controller.previewVideoPath()
            property var videoMeta: videoPath ? (overlay.controller.videoMetaCache[videoPath] || ({})) : ({})

            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 280
              radius: Theme.radiusM
              color: Theme.surfaceVariant
              border.color: Theme.outline
              border.width: 0.5
              clip: true

              Image {
                id: previewVideoThumb
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                source: {
                  if (!previewVideoPanel.videoPath)
                    return ""
                  var thumb = overlay.controller.videoThumbPaths[previewVideoPanel.videoPath]
                  return thumb ? "file://" + thumb : ""
                }
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                onStatusChanged: {
                  if (status === Image.Error && previewVideoPanel.videoPath) {
                    overlay.controller.removeVideoThumbPath(previewVideoPanel.videoPath)
                  }
                }
              }

              Text {
                visible: previewVideoThumb.status !== Image.Ready
                anchors.centerIn: parent
                text: "\uf03d"
                font.family: Theme.iconFont
                font.pixelSize: 48
                color: Theme.textMuted
              }

              Rectangle {
                visible: previewVideoThumb.status === Image.Ready
                anchors.centerIn: parent
                width: 48
                height: 48
                radius: 24
                color: Theme.alpha(Qt.black, 0.5)

                Text {
                  anchors.centerIn: parent
                  text: "\uf04b"
                  font.family: Theme.iconFont
                  font.pixelSize: 20
                  color: "white"
                }
              }
            }

            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: videoMetaColumn.implicitHeight + Theme.spacingM * 2
              radius: Theme.radiusM
              color: Theme.surface
              border.color: Theme.outline
              border.width: 0.5

              ColumnLayout {
                id: videoMetaColumn
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: 4

                TextEdit {
                  id: videoMetaText
                  Layout.fillWidth: true
                  Layout.preferredHeight: contentHeight
                  text: {
                    var item = overlay.controller.previewItem
                    if (!item)
                      return ""
                    var meta = previewVideoPanel.videoMeta || ({})
                    var path = previewVideoPanel.videoPath
                    var lines = []
                    var name = meta.name || (path ? path.split("/").pop() : "")
                    if (name)
                      lines.push("文件名: " + name)
                    if (meta.path || path)
                      lines.push("路径: " + (meta.path || path))

                    var parts = ["视频"]
                    var duration = Format.duration(meta.duration)
                    if (duration)
                      parts.push(duration)
                    if (meta.width && meta.height)
                      parts.push(meta.width + "x" + meta.height)
                    var size = Format.bytes(meta.size)
                    if (size)
                      parts.push(size)
                    if (item.fileMime)
                      parts.push(item.fileMime)
                    if (meta.format_name)
                      parts.push(meta.format_name)
                    var ext = path && path.lastIndexOf(".") !== -1 ? path.substring(path.lastIndexOf(".") + 1).toUpperCase() : ""
                    if (ext)
                      parts.push(ext)
                    lines.push("信息: " + parts.join(" | "))

                    if (meta.modified) {
                      lines.push("修改时间: " + meta.modified)
                    } else if (overlay.controller.videoMetaRunning && overlay.controller.videoMetaCurrentPath === path) {
                      lines.push("正在读取视频信息...")
                    }
                    return lines.join("\n")
                  }
                  font.pixelSize: Theme.fontSizeXS
                  color: Theme.textPrimary
                  wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
                  readOnly: true
                  selectByMouse: true
                  selectionColor: Theme.primary
                  selectedTextColor: "white"
                }
              }
            }
          }

          // HTML 内嵌图片预览
          AnimatedImage {
            id: previewHtmlImage
            visible: overlay.controller.previewItem && overlay.controller.previewItem.textType === "html" && overlay.controller.previewItem.htmlImageSrcs && overlay.controller.previewItem.htmlImageSrcs.length > 0 && overlay.controller.isLocalImagePath(overlay.controller.previewItem.htmlImageSrcs[0])
            width: parent.width
            source: (overlay.controller.previewItem && overlay.controller.previewItem.textType === "html" && overlay.controller.previewItem.htmlImageSrcs && overlay.controller.previewItem.htmlImageSrcs.length > 0 && overlay.controller.isLocalImagePath(overlay.controller.previewItem.htmlImageSrcs[0])) ? Logic.localFileUrl(overlay.controller.previewItem.htmlImageSrcs[0]) : ""
            fillMode: Image.PreserveAspectFit
            playing: true
            asynchronous: true
          }

          // 非可预览文件的信息列表
          ColumnLayout {
            id: previewFileInfo
            visible: overlay.controller.previewItem && overlay.controller.previewItem.isFile && (overlay.controller.previewItem.filePaths.length > 1 || (overlay.controller.previewItem.fileType !== "image" && overlay.controller.previewItem.fileType !== "gif" && overlay.controller.previewItem.fileType !== "video"))
            width: parent.width
            spacing: Theme.spacingM

            Text {
              Layout.alignment: Qt.AlignHCenter
              Layout.topMargin: Theme.spacingM
              text: overlay.controller.previewFilePaths.length + " 个文件"
              font.pixelSize: Theme.fontSizeL
              font.bold: true
              color: Theme.textPrimary
              visible: overlay.controller.previewFilePaths.length > 1
            }

            Repeater {
              model: overlay.controller.previewFilePaths

              Rectangle {
                id: fileEntry
                required property string modelData
                required property int index
                Layout.fillWidth: true
                Layout.preferredHeight: fileEntryRow.implicitHeight + Theme.spacingM * 2
                radius: Theme.radiusM
                color: Theme.surface
                border.color: Theme.outline
                border.width: 0.5

                readonly property string normalizedPath: Logic.normalizeLocalPath(modelData)
                readonly property string fileMime: overlay.controller.pathMimeCache[normalizedPath] || ""
                readonly property string fileExt: modelData.split(".").pop().toLowerCase()
                readonly property bool isImageFile: fileMime ? fileMime.startsWith("image/") : (Logic.imageExts.indexOf(fileExt) !== -1 || Logic.gifExts.indexOf(fileExt) !== -1)
                readonly property bool isGifFile: fileMime ? fileMime === "image/gif" : (fileExt === "gif")

                RowLayout {
                  id: fileEntryRow
                  anchors.fill: parent
                  anchors.margins: Theme.spacingM
                  spacing: Theme.spacingM

                  // 文件缩略图或图标
                  Rectangle {
                    Layout.preferredWidth: 48
                    Layout.preferredHeight: 48
                    Layout.alignment: Qt.AlignVCenter
                    radius: Theme.radiusS
                    color: Theme.surfaceVariant
                    clip: true

                    AnimatedImage {
                      anchors.fill: parent
                      anchors.margins: 2
                      visible: fileEntry.isGifFile
                      source: fileEntry.isGifFile ? "file://" + fileEntry.modelData : ""
                      fillMode: Image.PreserveAspectCrop
                      playing: true
                      asynchronous: true
                    }

                    Image {
                      anchors.fill: parent
                      anchors.margins: 2
                      visible: fileEntry.isImageFile && !fileEntry.isGifFile
                      source: (fileEntry.isImageFile && !fileEntry.isGifFile) ? "file://" + fileEntry.modelData : ""
                      fillMode: Image.PreserveAspectCrop
                      asynchronous: true
                    }

                    Text {
                      visible: !fileEntry.isImageFile
                      anchors.centerIn: parent
                      text: {
                        var ext = fileEntry.fileExt
                        var mime = fileEntry.fileMime
                        if (mime.startsWith("video/"))
                          return "\uf03d"
                        if (mime.startsWith("audio/"))
                          return "\uf001"
                        if (Logic.videoExts.indexOf(ext) !== -1)
                          return "\uf03d"
                        if (Logic.audioExts.indexOf(ext) !== -1)
                          return "\uf001"
                        if (Logic.archiveExts.indexOf(ext) !== -1)
                          return "\uf1c6"
                        if (Logic.docExts.indexOf(ext) !== -1)
                          return "\uf15c"
                        return "\uf15b"
                      }
                      font.family: Theme.iconFont
                      font.pixelSize: 20
                      color: Theme.textMuted
                    }
                  }

                  // 文件名与路径
                  ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 2

                    Text {
                      Layout.fillWidth: true
                      text: fileEntry.modelData.split("/").pop()
                      font.pixelSize: Theme.fontSizeM
                      font.bold: true
                      color: Theme.textPrimary
                      elide: Text.ElideMiddle
                      maximumLineCount: 1
                    }

                    Text {
                      Layout.fillWidth: true
                      text: fileEntry.modelData.substring(0, fileEntry.modelData.lastIndexOf("/"))
                      font.pixelSize: Theme.fontSizeXS
                      color: Theme.textMuted
                      elide: Text.ElideMiddle
                      maximumLineCount: 1
                    }
                  }
                }
              }
            }
          }

          // 文本预览（可选中）
          TextEdit {
            id: previewTextEdit
            visible: overlay.controller.previewItem && !overlay.controller.previewItem.isImage && !overlay.controller.previewItem.isFile && !(overlay.controller.previewItem.textType === "html" && overlay.controller.previewItem.htmlImageSrcs && overlay.controller.previewItem.htmlImageSrcs.length > 0 && overlay.controller.isLocalImagePath(overlay.controller.previewItem.htmlImageSrcs[0]))
            width: parent.width
            text: overlay.controller.previewFullText
            font.pixelSize: Theme.fontSizeM
            font.family: Theme.monoFont
            color: Theme.textPrimary
            wrapMode: TextEdit.WrapAtWordBoundaryOrAnywhere
            readOnly: true
            selectByMouse: true
            selectionColor: Theme.primary
            selectedTextColor: "white"
          }
        }

        // 预览滚动条
        Rectangle {
          visible: previewFlickable.contentHeight > previewFlickable.height
          anchors.right: parent.right
          y: (previewFlickable.contentHeight > previewFlickable.height) ? previewFlickable.contentY / (previewFlickable.contentHeight - previewFlickable.height) * (parent.height - height) : 0
          width: 6
          height: Math.max(30, parent.height * parent.height / previewFlickable.contentHeight)
          radius: 3
          color: pvScrollArea.pressed ? Theme.textMuted : Theme.alpha(Theme.textMuted, 0.5)

          MouseArea {
            id: pvScrollArea
            anchors.fill: parent
            drag.target: parent
            drag.axis: Drag.YAxis
            drag.minimumY: 0
            drag.maximumY: previewFlickable.height - parent.height

            onPositionChanged: {
              if (drag.active) {
                var ratio = parent.y / (previewFlickable.height - parent.height)
                previewFlickable.contentY = ratio * (previewFlickable.contentHeight - previewFlickable.height)
              }
            }
          }
        }
      }
    }
  }
}
