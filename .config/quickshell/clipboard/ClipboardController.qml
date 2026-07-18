// ClipboardController.qml — 剪贴板业务控制器（非可视）
//
// 把原先塞在 shell.qml 里的全部「数据 + 进程 + 调度」逻辑集中到这里：cliphist 列表加载、
// 分块解析、异步解码、mime 探测、图片/视频缩略图生成、视频元数据、过滤排序、二次激活复制、
// 删除等。纯函数都下沉到 ClipboardLogic.js；本文件只保留依赖运行时状态（mime 缓存、缓存目录、
// Process）或 Theme 的逻辑。UI（Clipboard.qml）实例化本控制器并绑定其属性。
//
// 设计要点：根对象 id 仍为 root，使内部大量 root.xxx 状态引用保持不变；对外通过属性暴露状态、
// 通过 closeRequested 信号请求 UI 关闭窗口。
import QtQuick
import Quickshell
import Quickshell.Io

import qs.Common
import "ClipboardLogic.js" as Logic

Scope {
  id: root

  // ============ 对外信号 ============
  /** 选中条目并完成复制后，请求 UI 关闭窗口 */
  signal closeRequested

  // ============ 状态 ============
  property var clipboardItems: []
  property var filteredItems: []
  property string searchText: ""
  property var activeTagFilters: []
  property var tagCounts: ({})
  property var itemIndexById: ({})
  property int selectedIndex: 0
  property bool loading: false
  property bool parsing: false
  property bool searchIndexing: false
  property int searchIndexedCount: 0
  property bool closing: false
  readonly property string cacheDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-clipboard"
  readonly property int clipboardListLimit: parseInt(Quickshell.env("QS_CLIPBOARD_LIST_LIMIT")) || 750
  readonly property int decodeChunkSize: parseInt(Quickshell.env("QS_CLIPBOARD_DECODE_CHUNK")) || 24
  readonly property int searchTextLimit: parseInt(Quickshell.env("QS_CLIPBOARD_SEARCH_TEXT_LIMIT")) || 20000

  // ============ 置顶（收藏）============
  // cliphist 无原生收藏概念，这里自建持久化收藏：内容快照存到独立目录，即使
  // cliphist 清空 / 历史轮换也不丢失。置顶项独立于 clipboardItems，仅在 filterItems 合并到最前。
  readonly property string pinDir: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/qs-clipboard/pins"
  readonly property string pinFile: pinDir + "/pins.json"
  property var pinnedItems: []          // 置顶项数组（最新置顶在前）
  property var pinnedIdSet: ({})         // id -> true，用于在活动列表里去重

  // 标签过滤可选项（供过滤条渲染）
  readonly property var tagFilterOptions: [
    { id: "text", label: "文本", icon: "" },
    { id: "code", label: "代码", icon: "" },
    { id: "url", label: "链接", icon: "" },
    { id: "image", label: "图片", icon: "" },
    { id: "file", label: "文件", icon: "" },
    { id: "video", label: "视频", icon: "" },
    { id: "html", label: "HTML", icon: "" },
    { id: "color", label: "颜色", icon: "#" }
  ]

  // 各类文件扩展名（转发自逻辑库，供 UI 选择图标）
  readonly property var imageExts: Logic.imageExts
  readonly property var gifExts: Logic.gifExts
  readonly property var videoExts: Logic.videoExts
  readonly property var audioExts: Logic.audioExts
  readonly property var archiveExts: Logic.archiveExts
  readonly property var docExts: Logic.docExts

  // ============ 预览状态 ============
  property bool previewVisible: false
  property var previewItem: null
  property string previewFullText: ""
  property string saveImageStatus: ""
  property bool saveImageRunning: false
  // 从解码内容里重新解析出的文件路径（供预览层使用）
  property var previewFilePaths: {
    if (!previewItem || !previewItem.isFile || !previewFullText)
      return previewItem ? previewItem.filePaths : []
    var paths = Logic.extractFilePaths(previewFullText)
    return paths.length > 0 ? paths : (previewItem ? previewItem.filePaths : [])
  }

  // ============ 加载缓冲与缓存 ============
  property string clipboardBuffer: ""
  property string asyncDecodeBuffer: ""
  property string mimeProbeBuffer: ""
  property bool mimeProbePending: false
  property var pathMimeCache: ({})
  property var videoMetaCache: ({})
  property var mimeProbeTasks: ({})
  property int mimeProbeSeq: 0
  property string videoMetaBuffer: ""
  property string videoMetaPendingPath: ""
  property var pendingDecodeIds: []
  property int pendingDecodeCursor: 0
  // 分块解析状态
  property var pendingParseEntries: []
  property var parseItemsBuffer: []
  property var parseSeen: ({})
  readonly property int parseFirstBatch: 15
  readonly property int parseChunkSize: parseInt(Quickshell.env("QS_CLIPBOARD_PARSE_CHUNK")) || 60

  // ============ 进程：加载 cliphist 列表 ============
  Process {
    id: loadClipboard
    command: ["bash", "-c", "cliphist list | awk -v limit=" + root.clipboardListLimit + " 'BEGIN{count=0} /^[0-9]+\\t/{ count++; if (count > limit) exit } { print }'"]
    stdout: SplitParser {
      splitMarker: ""
      onRead: data => {
        root.clipboardBuffer += data
      }
    }
    onExited: code => {
      if (root.closing) {
        root.clipboardBuffer = ""
        root.loading = false
        return
      }
      if (code === 0) {
        try {
          root.parseClipboardData(root.clipboardBuffer)
        } catch (e) {
          console.error("parseClipboardData error:", e)
          root.parsing = false
          root.loading = false
        }
      } else {
        root.parsing = false
        root.loading = false
      }
      root.clipboardBuffer = ""
    }
  }

  // ============ 进程：异步解码（用于搜索索引与富信息提取） ============
  Process {
    id: asyncDecodeProcess
    command: ["echo"]
    stdout: SplitParser {
      splitMarker: ""
      onRead: data => {
        root.asyncDecodeBuffer += data
      }
    }
    onExited: code => {
      if (root.closing) {
        root.asyncDecodeBuffer = ""
        return
      }
      if (code === 0 && root.asyncDecodeBuffer) {
        root.updateDecodedEntries(root.asyncDecodeBuffer)
      }
      root.asyncDecodeBuffer = ""
      if (root.pendingDecodeCursor < root.pendingDecodeIds.length) {
        decodeChunkTimer.restart()
      } else {
        root.searchIndexing = false
      }
    }
  }

  // ============ 进程：mime 探测 ============
  Process {
    id: mimeProbeProcess
    command: ["echo"]
    stdout: SplitParser {
      splitMarker: ""
      onRead: data => {
        root.mimeProbeBuffer += data
      }
    }
    onExited: code => {
      if (root.closing) {
        root.mimeProbeBuffer = ""
        root.mimeProbePending = false
        return
      }
      if (code === 0 && root.mimeProbeBuffer) {
        root.applyMimeProbeData(root.mimeProbeBuffer)
      }
      root.mimeProbeBuffer = ""
      if (root.mimeProbePending) {
        root.mimeProbePending = false
        root.startMimeProbe()
      }
    }
  }

  /**
   * 把异步解码回来的内容回填到对应条目（搜索索引、HTML 图片 / 纯文本、文件路径等）。
   * @param {string} data 解码进程输出
   */
  function updateDecodedEntries(data) {
    if (root.closing)
      return
    var marker = "===CLIP:"
    var endMarker = "===\n"
    var pos = 0
    var visualUpdated = false
    var searchUpdated = false
    data = Logic.sanitizeClipboardText(data)
    while (true) {
      var start = data.indexOf(marker, pos)
      if (start === -1)
        break
      var idStart = start + marker.length
      var idEnd = data.indexOf(endMarker, idStart)
      if (idEnd === -1)
        break
      var id = data.substring(idStart, idEnd)
      var contentStart = idEnd + endMarker.length
      var nextMarker = data.indexOf(marker, contentStart)
      var content = nextMarker === -1 ? data.substring(contentStart) : data.substring(contentStart, nextMarker)

      var idx = root.itemIndexById[String(id)]
      if (idx !== undefined) {
        var item = clipboardItems[idx]
        var itemChanged = false
        var allowSearchContent = !item.isImage && (item.isFile || item.textType === "html" || !Logic.isLikelyBinaryNoiseText(content))
        var nextSearchLower = allowSearchContent ? Logic.sanitizeClipboardText(content).toLowerCase() : ""
        if (!item.searchIndexed) {
          item.searchIndexed = true
          root.searchIndexedCount++
        }
        if (nextSearchLower && item.decodedSearchLower !== nextSearchLower) {
          item.decodedSearchLower = nextSearchLower
          searchUpdated = true
          itemChanged = true
        }

        if (item.textType === "html") {
          var srcs = Logic.extractHtmlImageSrcs(content)
          if (srcs.length > 0) {
            var nextPreview = srcs.map(function (s) {
              if (s.startsWith("data:"))
                return "[base64 image]"
              return s.split("/").pop()
            }).join(", ")
            if (JSON.stringify(item.htmlImageSrcs || []) !== JSON.stringify(srcs)) {
              item.htmlImageSrcs = srcs
              visualUpdated = true
              itemChanged = true
            }
            if (item.preview !== nextPreview) {
              item.preview = nextPreview
              visualUpdated = true
              itemChanged = true
            }
            if (item.htmlPlainText) {
              item.htmlPlainText = ""
              visualUpdated = true
              itemChanged = true
            }
            if (item.htmlPreferPlain) {
              item.htmlPreferPlain = false
              visualUpdated = true
              itemChanged = true
            }
          } else {
            if (item.htmlImageSrcs && item.htmlImageSrcs.length > 0) {
              item.htmlImageSrcs = []
              visualUpdated = true
              itemChanged = true
            }
            var plain = Logic.htmlToPlainText(content)
            var preferPlain = Logic.shouldTreatHtmlAsPlainText(content, plain)
            if (item.htmlPlainText !== plain) {
              item.htmlPlainText = plain
              visualUpdated = true
              itemChanged = true
            }
            if (item.htmlPreferPlain !== preferPlain) {
              item.htmlPreferPlain = preferPlain
              visualUpdated = true
              itemChanged = true
            }
            if (preferPlain && plain) {
              var plainPreview = Logic.previewText(plain)
              if (item.preview !== plainPreview) {
                item.preview = plainPreview
                visualUpdated = true
                itemChanged = true
              }
            }
          }
        } else if (item.isFile) {
          var paths = Logic.extractFilePaths(content)
          if (paths.length > 0) {
            var nextType = root.classifyFile(paths[0])
            var nextPreview2 = paths.map(function (p) {
              return p.split("/").pop()
            }).join(", ")
            if (JSON.stringify(item.filePaths || []) !== JSON.stringify(paths)) {
              item.filePaths = paths
              visualUpdated = true
              itemChanged = true
            }
            if (item.fileType !== nextType) {
              item.fileType = nextType
              visualUpdated = true
              itemChanged = true
            }
            if (item.preview !== nextPreview2) {
              item.preview = nextPreview2
              visualUpdated = true
              itemChanged = true
            }
          }
        }

        if (itemChanged) {
          root.rebuildItemDerivedFields(item)
        }
      }
      pos = nextMarker === -1 ? data.length : nextMarker
    }
    if (visualUpdated || (searchUpdated && root.hasKeywordSearch())) {
      clipboardItems = clipboardItems.slice()
      if (visualUpdated)
        rebuildTagCounts()
      filterItems()
      if (visualUpdated)
        queueMimeProbe()
    }
  }

  // ============ 标签与派生字段 ============

  /** 重建条目的标签 / 标签集合 / 搜索索引串 / 是否有可视预览等派生字段 */
  function rebuildItemDerivedFields(item) {
    var tags = Logic.buildItemTags(item)
    var tagSet = {}
    for (var i = 0; i < tags.length; i++) {
      tagSet[tags[i]] = true
    }

    var searchParts = []
    searchParts.push(item.preview || "")
    if (item.filePaths && item.filePaths.length > 0)
      searchParts.push(item.filePaths.join(" "))
    if (item.textType === "html" && item.htmlPlainText)
      searchParts.push(item.htmlPlainText)
    searchParts.push(tags.join(" "))
    if (item.isImage && item.imageExt)
      searchParts.push(item.imageExt)

    item.tags = tags
    item.tagSet = tagSet
    var searchBlob = Logic.sanitizeClipboardText(searchParts.join(" ")).toLowerCase()
    if (item.decodedSearchLower)
      searchBlob += " " + item.decodedSearchLower
    item.searchBlobLower = searchBlob
    item.hasVisualPreview = item.isImage || (item.isFile && (item.fileType === "image" || item.fileType === "gif" || item.fileType === "video")) || (item.textType === "html" && item.htmlImageSrcs && item.htmlImageSrcs.length > 0 && root.isLocalImagePath(item.htmlImageSrcs[0]))
  }

  /** 当前搜索是否含关键词 */
  function hasKeywordSearch() {
    return Logic.parseSearchQuery(searchText).keyword.length > 0
  }

  /** 重建 id → 索引映射 */
  function rebuildItemIndexMap() {
    var map = {}
    for (var i = 0; i < clipboardItems.length; i++) {
      map[String(clipboardItems[i].id)] = i
    }
    itemIndexById = map
  }

  /** 重建各标签的计数 */
  function rebuildTagCounts() {
    var counts = {}
    for (var i = 0; i < clipboardItems.length; i++) {
      var tags = clipboardItems[i].tags || []
      for (var j = 0; j < tags.length; j++) {
        var tag = tags[j]
        counts[tag] = (counts[tag] || 0) + 1
      }
    }
    tagCounts = counts
  }

  /** 取某标签计数 */
  function tagCount(tag) {
    return tagCounts[tag] || 0
  }

  /** 切换某标签的激活状态 */
  function toggleTagFilter(tag) {
    var normalized = Logic.normalizeTag(tag)
    if (!normalized)
      return
    var next = activeTagFilters.slice()
    var idx = next.indexOf(normalized)
    if (idx !== -1)
      next.splice(idx, 1)
    else
      next.push(normalized)
    activeTagFilters = next
  }

  /** 清空所有标签过滤 */
  function clearTagFilters() {
    activeTagFilters = []
  }

  // ============ 异步解码调度 ============

  /** 排队异步解码一批条目 id */
  function queueAsyncDecode(ids) {
    if (root.closing)
      return
    pendingDecodeIds = ids ? ids.slice() : []
    pendingDecodeCursor = 0
    searchIndexedCount = 0
    searchIndexing = pendingDecodeIds.length > 0
    if (pendingDecodeIds.length > 0) {
      decodeChunkTimer.restart()
    }
  }

  /** 解码下一批（分块，避免一次性 fork 过多进程） */
  function runNextDecodeChunk() {
    if (root.closing)
      return
    if (asyncDecodeProcess.running)
      return
    if (!pendingDecodeIds || pendingDecodeCursor >= pendingDecodeIds.length)
      return
    var end = Math.min(pendingDecodeCursor + decodeChunkSize, pendingDecodeIds.length)
    var chunk = pendingDecodeIds.slice(pendingDecodeCursor, end)
    pendingDecodeCursor = end

    if (chunk.length === 0)
      return
    var limit = Math.max(1024, root.searchTextLimit)
    var cmd = chunk.map(function (id) {
      return "printf '===CLIP:" + id + "===\\n'; cliphist decode '" + id + "' | head -c " + limit
    }).join("; ")
    asyncDecodeProcess.command = ["bash", "-c", cmd]
    asyncDecodeProcess.running = true
  }

  // ============ mime 探测 ============

  /** 排队 mime 探测（若进程忙则置 pending） */
  function queueMimeProbe() {
    if (root.closing)
      return
    if (mimeProbeProcess.running) {
      mimeProbePending = true
      return
    }
    startMimeProbe()
  }

  /** 启动一次 mime 探测：对所有文件 / HTML 图片路径批量 file --mime-type */
  function startMimeProbe() {
    if (root.closing)
      return
    var tasks = {}
    var parts = []
    var taskCount = 0
    var maxTasks = 512
    var queuedPaths = {}

    function addTask(kind, id, rawPath) {
      if (taskCount >= maxTasks)
        return
      var path = Logic.normalizeLocalPath(rawPath)
      if (!path || path.charAt(0) !== "/")
        return
      if (queuedPaths[path])
        return
      if (root.pathMimeCache[path] !== undefined)
        return
      var token = String(++root.mimeProbeSeq)
      tasks[token] = { kind: kind, id: String(id), path: path }
      parts.push('printf "===MIME:' + token + '===\\n"; file -Lb --mime-type -- ' + Logic.shellQuote(path) + ' 2>/dev/null || true')
      queuedPaths[path] = true
      taskCount++
    }

    for (var i = 0; i < clipboardItems.length; i++) {
      var item = clipboardItems[i]
      if (item.isFile && item.filePaths && item.filePaths.length > 0) {
        for (var f = 0; f < item.filePaths.length; f++) {
          addTask("FILE", item.id, item.filePaths[f])
        }
      }
      if (item.textType === "html" && item.htmlImageSrcs && item.htmlImageSrcs.length > 0) {
        for (var s = 0; s < item.htmlImageSrcs.length; s++) {
          addTask("HTML", item.id, item.htmlImageSrcs[s])
        }
      }
    }

    if (parts.length === 0)
      return
    root.mimeProbeTasks = tasks
    root.mimeProbeBuffer = ""
    mimeProbeProcess.command = ["bash", "-c", parts.join("; ")]
    mimeProbeProcess.running = true
  }

  /** 应用 mime 探测结果，更新文件类型分类，必要时触发视频缩略图生成 */
  function applyMimeProbeData(data) {
    if (root.closing)
      return
    var marker = "===MIME:"
    var endMarker = "===\n"
    var pos = 0
    var updated = false
    var newCache = Object.assign({}, root.pathMimeCache)

    while (true) {
      var start = data.indexOf(marker, pos)
      if (start === -1)
        break
      var tokenStart = start + marker.length
      var tokenEnd = data.indexOf(endMarker, tokenStart)
      if (tokenEnd === -1)
        break
      var token = data.substring(tokenStart, tokenEnd)
      var contentStart = tokenEnd + endMarker.length
      var nextMarker = data.indexOf(marker, contentStart)
      var content = nextMarker === -1 ? data.substring(contentStart) : data.substring(contentStart, nextMarker)
      var mime = content.trim().split(/\s+/)[0]
      var task = root.mimeProbeTasks[token]

      if (task && mime) {
        var prevMime = newCache[task.path] || ""
        newCache[task.path] = mime
        if (prevMime !== mime)
          updated = true

        var idx = root.itemIndexById[task.id]
        if (idx !== undefined) {
          var item = clipboardItems[idx]
          var itemChanged = false
          if (task.kind === "FILE" && item.isFile && item.filePaths && item.filePaths.length > 0) {
            var firstPath = Logic.normalizeLocalPath(item.filePaths[0])
            var firstMime = firstPath ? (newCache[firstPath] || "") : ""
            var nextType = firstMime ? Logic.classifyFileByMime(firstMime, firstPath || item.filePaths[0]) : Logic.classifyFileByExt(firstPath || item.filePaths[0])
            if (item.fileMime !== firstMime) {
              item.fileMime = firstMime
              updated = true
              itemChanged = true
            }
            if (item.fileType !== nextType) {
              item.fileType = nextType
              updated = true
              itemChanged = true
            }
          } else if (task.kind === "HTML" && item.textType === "html") {
            if (item.htmlImageMime !== mime) {
              item.htmlImageMime = mime
              updated = true
            }
          }
          if (itemChanged)
            root.rebuildItemDerivedFields(item)
        }
      }

      pos = nextMarker === -1 ? data.length : nextMarker
    }

    root.pathMimeCache = newCache
    if (updated) {
      clipboardItems = clipboardItems.slice()
      rebuildTagCounts()
      filterItems()
      if (clipboardItems.some(function (i) {
        return i.isFile && i.fileType === "video"
      })) {
        startVideoThumbGen()
      }
    }
  }

  // ============ 文件 / 图片类型判定（依赖 mime 缓存，故留在控制器） ============

  /** 综合 mime 缓存与扩展名分类文件 */
  function classifyFile(path) {
    var normalized = Logic.normalizeLocalPath(path)
    var mime = normalized ? (root.pathMimeCache[normalized] || "") : ""
    if (mime)
      return Logic.classifyFileByMime(mime, normalized || path)
    return Logic.classifyFileByExt(normalized || path)
  }

  /** 判断路径是否为可预览的本地图片 */
  function isLocalImagePath(path) {
    var src = String(path === undefined || path === null ? "" : path)
    if (!src || src.startsWith("data:") || /^https?:\/\//i.test(src))
      return false
    var normalized = Logic.normalizeLocalPath(src)
    if (!normalized || normalized.charAt(0) !== "/")
      return false
    var mime = root.pathMimeCache[normalized] || ""
    if (!mime)
      return true
    return mime.startsWith("image/")
  }

  /** 判断路径是否为本地动图（gif/apng/webp） */
  function isLocalAnimatedImagePath(path) {
    var normalized = Logic.normalizeLocalPath(path)
    if (!normalized || normalized.charAt(0) !== "/")
      return false
    var mime = root.pathMimeCache[normalized] || ""
    return mime === "image/gif" || mime === "image/apng" || mime === "image/webp"
  }

  /** 取二进制图片在缓存目录中的解码路径 */
  function imagePathById(id) {
    return root.imagePaths[id] ? root.imagePaths[id] : (cacheDir + "/" + id + ".png")
  }

  // ============ 类型徽标（依赖 Theme 配色，故留在控制器） ============

  /**
   * 返回条目的类型徽标信息。
   * @param {object} item 条目
   * @returns {{ label: string, icon: string, color: color }} 徽标
   */
  function typeBadgeInfo(item) {
    if (item.isImage) {
      var ext = (item.imageExt || "png").toUpperCase()
      if (ext === "GIF")
        return { label: "GIF", icon: "", color: Theme.primary }
      return { label: "IMG", icon: "", color: Theme.primary }
    }
    if (item.isFile) {
      if (item.filePaths.length > 1) {
        return { label: item.filePaths.length + "F", icon: "", color: Theme.tertiary }
      }
      switch (item.fileType) {
      case "gif":
        return { label: "GIF", icon: "", color: Theme.primary }
      case "image":
        return { label: "IMG", icon: "", color: Theme.primary }
      case "video":
        return { label: "VID", icon: "", color: "#e67e22" }
      case "audio":
        return { label: "AUD", icon: "", color: "#9b59b6" }
      case "archive":
        return { label: "ZIP", icon: "", color: "#f39c12" }
      case "document":
        return { label: "DOC", icon: "", color: Theme.tertiary }
      default:
        return { label: "FILE", icon: "", color: Theme.tertiary }
      }
    }
    // 文本子类型
    switch (item.textType) {
    case "html":
      if (item.htmlPreferPlain)
        return { label: "TEXT", icon: "", color: Theme.secondary }
      return { label: "HTML", icon: "", color: "#e44d26" }
    case "url":
      return { label: "URL", icon: "", color: "#2980b9" }
    case "path":
      return { label: "PATH", icon: "", color: "#27ae60" }
    case "color":
      return { label: "CLR", icon: "#", color: Theme.primary }
    case "code":
      return { label: "CODE", icon: "", color: "#e74c3c" }
    default:
      return { label: "TEXT", icon: "", color: Theme.secondary }
    }
  }

  // ============ 解析剪贴板数据 ============

  /** 解析单条 cliphist 条目，识别类型并构造条目对象（不可识别 / 去重命中返回 null） */
  function parseOneEntry(entry, seen) {
    var id = entry.id
    var rawContent = entry.content
    var content = Logic.sanitizeClipboardText(rawContent)
    var trimmedContent = content.trim()
    var isImage = trimmedContent.startsWith("[[ binary data")
    var isPlaceholderImageText = Logic.placeholderImageMime(trimmedContent).length > 0
    if (isPlaceholderImageText)
      return null

    var imageExt = isImage ? Logic.binaryExtFromMeta(trimmedContent) : ""
    var imageDimensions = isImage ? Logic.binaryDimensionsFromMeta(trimmedContent) : ""
    var imageSize = isImage ? Logic.binarySizeFromMeta(trimmedContent) : ""
    var isFile = !isImage && content.indexOf("file://") !== -1 && !/<\s*(img|html|body|div|span|p|meta|table)\b/i.test(content)

    var filePaths = []
    var fileType = ""
    if (isFile) {
      filePaths = Logic.extractFilePaths(content)
      if (filePaths.length === 0) {
        isFile = false
      } else {
        fileType = root.classifyFile(filePaths[0])
      }
    }

    var textType = ""
    var htmlImageSrcs = []
    var htmlPlainText = ""
    var htmlPreferPlain = false
    if (!isImage && !isFile) {
      if (Logic.isLikelyBinaryNoiseText(rawContent))
        return null
      textType = Logic.classifyText(content)
      if (textType === "html") {
        htmlImageSrcs = Logic.extractHtmlImageSrcs(content)
        if (htmlImageSrcs.length === 0) {
          htmlPlainText = Logic.htmlToPlainText(content)
          htmlPreferPlain = Logic.shouldTreatHtmlAsPlainText(content, htmlPlainText)
        }
      }
    }

    var preview = ""
    if (isImage) {
      var parts = []
      if (imageExt)
        parts.push(imageExt.toUpperCase())
      if (imageDimensions)
        parts.push(imageDimensions)
      if (imageSize)
        parts.push(imageSize)
      preview = parts.length > 0 ? parts.join(" | ") : "image"
    } else if (isFile) {
      preview = filePaths.map(function (p) {
        return p.split("/").pop()
      }).join(", ")
    } else if (textType === "html" && htmlImageSrcs.length > 0) {
      preview = htmlImageSrcs.map(function (s) {
        if (s.startsWith("data:"))
          return "[base64 image]"
        return s.split("/").pop()
      }).join(", ")
    } else if (textType === "html" && htmlPreferPlain && htmlPlainText) {
      preview = Logic.previewText(htmlPlainText)
    } else {
      preview = Logic.previewText(content)
    }

    var key = isImage ? ("img:" + content) : (isFile ? ("file:" + filePaths.join("|")) : ("text:" + id))
    if (seen[key])
      return null
    seen[key] = true

    var item = {
      id: id,
      isImage: isImage,
      imageExt: imageExt,
      imageDimensions: imageDimensions,
      imageSize: imageSize,
      isFile: isFile,
      fileType: fileType,
      fileMime: (isFile && filePaths.length > 0) ? (root.pathMimeCache[Logic.normalizeLocalPath(filePaths[0])] || "") : "",
      filePaths: filePaths,
      textType: textType,
      htmlImageSrcs: htmlImageSrcs,
      htmlImageMime: "",
      htmlPlainText: htmlPlainText,
      htmlPreferPlain: htmlPreferPlain,
      rawContent: isFile ? content.trim() : "",
      imagePath: "",
      preview: preview,
      colorValue: textType === "color" ? Logic.normalizeColorValue(trimmedContent) : "",
      decodedSearchLower: "",
      searchIndexed: false
    }
    root.rebuildItemDerivedFields(item)
    return item
  }

  /** 解析完成后调度后台任务：异步解码、图片解码、视频缩略图、mime 探测 */
  function scheduleBackgroundTasks(items) {
    if (root.closing)
      return
    var decodeIds = []
    for (var j = 0; j < items.length; j++) {
      if (!items[j].isImage) {
        decodeIds.push(items[j].id)
      }
    }
    root.queueAsyncDecode(decodeIds)

    if (items.some(function (i) {
      return i.isImage
    })) {
      imageDecodeStartTimer.restart()
    }
    if (items.some(function (i) {
      return i.isFile && i.fileType === "video"
    })) {
      videoThumbStartTimer.restart()
    }
    mimeProbeStartTimer.restart()
  }

  /** 解析整个 cliphist 列表：先渲染首屏，再分帧解析其余条目 */
  function parseClipboardData(data) {
    if (root.closing)
      return
    root.parsing = true
    root.loading = true
    var rawLines = data.trim().split("\n")
    var entries = []
    for (var i = 0; i < rawLines.length; i++) {
      var rl = rawLines[i]
      if (!rl && entries.length === 0)
        continue
      var ti = rl.indexOf("\t")
      if (ti > 0 && /^\d+$/.test(rl.substring(0, ti))) {
        entries.push({
          id: rl.substring(0, ti),
          content: rl.substring(ti + 1)
        })
      } else if (entries.length > 0) {
        entries[entries.length - 1].content += "\n" + rl
      }
    }

    // 阶段一：解析首批以便立即渲染
    var seen = {}
    var items = []
    var batchEnd = Math.min(entries.length, root.parseFirstBatch)
    for (var b = 0; b < batchEnd; b++) {
      var item = parseOneEntry(entries[b], seen)
      if (item)
        items.push(item)
    }
    root.parseItemsBuffer = items
    root.clipboardItems = items
    root.rebuildItemIndexMap()
    root.rebuildTagCounts()
    root.filterItems()

    // 阶段二：把剩余条目排到下一帧
    if (batchEnd < entries.length) {
      root.pendingParseEntries = entries.slice(batchEnd)
      root.parseSeen = seen
      parseRestTimer.restart()
    } else {
      root.pendingParseEntries = []
      root.parseItemsBuffer = items
      root.parsing = false
      root.loading = false
      scheduleBackgroundTasks(items)
    }
  }

  /** 分帧解析剩余条目 */
  function parseRemainingEntries() {
    if (root.closing)
      return
    var seen = root.parseSeen
    var items = root.parseItemsBuffer.slice()
    var entries = root.pendingParseEntries
    var end = Math.min(entries.length, root.parseChunkSize)
    for (var i = 0; i < end; i++) {
      var item = parseOneEntry(entries[i], seen)
      if (item)
        items.push(item)
    }
    root.pendingParseEntries = entries.slice(end)
    root.parseItemsBuffer = items
    if (root.pendingParseEntries.length > 0) {
      parseRestTimer.restart()
    } else {
      root.clipboardItems = items
      root.rebuildItemIndexMap()
      root.rebuildTagCounts()
      root.filterItems()
      root.parseSeen = ({})
      root.parseItemsBuffer = []
      root.parsing = false
      root.loading = false
      scheduleBackgroundTasks(items)
    }
  }

  // ============ 图片解码 ============
  property var imageQueue: []
  property int imageIndex: 0
  property var imagePaths: ({})

  Process {
    id: decodeImage
    property string currentId: ""
    property string currentPath: ""
    command: ["bash", "-c", "echo"]
    onExited: code => {
      if (root.closing)
        return
      if (code === 0 && decodeImage.currentId && decodeImage.currentPath) {
        var newPaths = Object.assign({}, root.imagePaths)
        newPaths[decodeImage.currentId] = decodeImage.currentPath
        root.imagePaths = newPaths
      }
      root.imageIndex++
      root.decodeNextImage()
    }
  }

  /** 收集待解码的二进制图片 id，建缓存目录后逐个解码 */
  function startImageDecode() {
    if (root.closing)
      return
    var ids = []
    for (var i = 0; i < clipboardItems.length; i++) {
      var item = clipboardItems[i]
      if (!item.isImage)
        continue
      if (root.imagePaths[item.id])
        continue
      ids.push(item.id)
    }
    imageQueue = ids
    imageIndex = 0
    if (imageQueue.length > 0) {
      mkCacheDir.running = true
    }
  }

  Process {
    id: mkCacheDir
    command: ["mkdir", "-p", cacheDir]
    onExited: {
      if (!root.closing)
        root.decodeNextImage()
    }
  }

  /** 解码队列里的下一张图片到缓存目录 */
  function decodeNextImage() {
    if (root.closing)
      return
    if (imageIndex >= imageQueue.length)
      return
    var id = imageQueue[imageIndex]
    var ext = "png"
    var idx = root.itemIndexById[String(id)]
    if (idx !== undefined) {
      var item = clipboardItems[idx]
      if (item && item.isImage)
        ext = item.imageExt || "png"
    }
    decodeImage.currentId = id
    decodeImage.currentPath = cacheDir + "/" + id + "." + ext
    decodeImage.command = ["bash", "-c", "cliphist decode '" + id + "' > '" + decodeImage.currentPath + "' 2>/dev/null"]
    decodeImage.running = true
  }

  // ============ 视频缩略图生成 ============
  property var videoQueue: []
  property int videoIndex: 0
  property var videoThumbPaths: ({})
  property bool videoThumbPending: false

  Process {
    id: genVideoThumb
    property string currentPath: ""
    property string output: ""
    command: ["bash", "-c", "echo"]
    stdout: SplitParser {
      splitMarker: ""
      onRead: data => {
        genVideoThumb.output += data
      }
    }
    onExited: code => {
      if (root.closing)
        return
      if (code === 0 && genVideoThumb.currentPath && genVideoThumb.output.trim() === "OK") {
        var thumbFile = root.cacheDir + "/vthumb_" + Qt.md5(genVideoThumb.currentPath) + ".png"
        var newPaths = Object.assign({}, root.videoThumbPaths)
        newPaths[genVideoThumb.currentPath] = thumbFile
        root.videoThumbPaths = newPaths
      } else if (genVideoThumb.currentPath && root.videoThumbPaths[genVideoThumb.currentPath]) {
        var cleanedPaths = Object.assign({}, root.videoThumbPaths)
        delete cleanedPaths[genVideoThumb.currentPath]
        root.videoThumbPaths = cleanedPaths
      }
      genVideoThumb.output = ""
      root.videoIndex++
      if (root.videoIndex < root.videoQueue.length) {
        root.genNextVideoThumb()
      } else if (root.videoThumbPending) {
        root.videoThumbPending = false
        root.startVideoThumbGen()
      }
    }
  }

  /** 收集需要缩略图的视频文件路径，建缓存目录后逐个生成 */
  function startVideoThumbGen() {
    if (root.closing)
      return
    if (genVideoThumb.running) {
      root.videoThumbPending = true
      return
    }
    var paths = []
    var seen = {}
    for (var i = 0; i < clipboardItems.length; i++) {
      var item = clipboardItems[i]
      if (item.isFile && item.fileType === "video" && item.filePaths.length > 0) {
        var path = Logic.normalizeLocalPath(item.filePaths[0])
        if (!path)
          continue
        if (seen[path])
          continue
        if (root.videoThumbPaths[path])
          continue
        seen[path] = true
        paths.push(path)
      }
    }
    videoQueue = paths
    videoIndex = 0
    if (paths.length > 0) {
      mkCacheDir2.running = true
    }
  }

  /** 移除某视频缩略图缓存（缩略图加载失败时调用） */
  function removeVideoThumbPath(rawPath) {
    var path = Logic.normalizeLocalPath(rawPath)
    if (!path || !root.videoThumbPaths[path])
      return
    var nextPaths = Object.assign({}, root.videoThumbPaths)
    delete nextPaths[path]
    root.videoThumbPaths = nextPaths
  }

  Process {
    id: mkCacheDir2
    command: ["mkdir", "-p", cacheDir]
    onExited: {
      if (!root.closing)
        root.genNextVideoThumb()
    }
  }

  /** 用 ffmpeg / ffmpegthumbnailer 生成队列里下一个视频的缩略图 */
  function genNextVideoThumb() {
    if (root.closing)
      return
    if (videoIndex >= videoQueue.length)
      return
    var filePath = videoQueue[videoIndex]
    genVideoThumb.currentPath = filePath
    genVideoThumb.output = ""
    var thumbFile = cacheDir + "/vthumb_" + Qt.md5(filePath) + ".png"
    genVideoThumb.command = ["bash", "-c", 'rm -f -- ' + Logic.shellQuote(thumbFile) + '; ' + 'if command -v ffmpeg >/dev/null 2>&1; then ' + 'ffmpeg -hide_banner -loglevel error -y -i ' + Logic.shellQuote(filePath) + ' -frames:v 1 -vf "scale=256:-1:force_original_aspect_ratio=decrease" -vcodec png -f image2 ' + Logic.shellQuote(thumbFile) + '; ' + 'elif command -v ffmpegthumbnailer >/dev/null 2>&1; then ' + 'ffmpegthumbnailer -i ' + Logic.shellQuote(filePath) + ' -o ' + Logic.shellQuote(thumbFile) + ' -s 256 -q 8; ' + 'fi; ' + 'if test -s ' + Logic.shellQuote(thumbFile) + ' && file -Lb --mime-type -- ' + Logic.shellQuote(thumbFile) + ' | grep -q "^image/"; then printf OK; else rm -f -- ' + Logic.shellQuote(thumbFile) + '; exit 1; fi']
    genVideoThumb.running = true
  }

  // ============ 视频元数据 ============
  // 暴露给预览层判断「是否正在读取某视频的信息」
  readonly property alias videoMetaRunning: videoMetaProcess.running
  readonly property alias videoMetaCurrentPath: videoMetaProcess.currentPath

  Process {
    id: videoMetaProcess
    property string currentPath: ""
    command: ["bash", "-c", "echo"]
    stdout: SplitParser {
      splitMarker: ""
      onRead: data => {
        root.videoMetaBuffer += data
      }
    }
    onExited: code => {
      if (root.closing)
        return
      if (code === 0 && videoMetaProcess.currentPath) {
        var nextCache = Object.assign({}, root.videoMetaCache)
        nextCache[videoMetaProcess.currentPath] = root.parseVideoMetaData(root.videoMetaBuffer, videoMetaProcess.currentPath)
        root.videoMetaCache = nextCache
      }
      root.videoMetaBuffer = ""
      if (root.videoMetaPendingPath) {
        var pendingPath = root.videoMetaPendingPath
        root.videoMetaPendingPath = ""
        root.startVideoMetaProbe(pendingPath)
      }
    }
  }

  /** 启动视频元数据探测（ffprobe + stat），同一时刻只跑一个，多余的排到 pending */
  function startVideoMetaProbe(rawPath) {
    if (root.closing)
      return
    var path = Logic.normalizeLocalPath(rawPath)
    if (!path || root.videoMetaCache[path])
      return
    if (videoMetaProcess.running) {
      root.videoMetaPendingPath = path
      return
    }

    root.videoMetaBuffer = ""
    videoMetaProcess.currentPath = path
    videoMetaProcess.command = ["bash", "-c", 'p=' + Logic.shellQuote(path) + '; ' + 'printf "path=%s\\n" "$p"; ' + 'printf "name=%s\\n" "$(basename -- "$p")"; ' + 'printf "size=%s\\n" "$(stat -c %s -- "$p" 2>/dev/null || stat -f %z -- "$p" 2>/dev/null || true)"; ' + 'printf "modified=%s\\n" "$(stat -c %y -- "$p" 2>/dev/null | cut -d. -f1 || true)"; ' + 'if command -v ffprobe >/dev/null 2>&1; then ' + 'ffprobe -v error -select_streams v:0 -show_entries stream=width,height,duration:format=duration,format_name -of default=noprint_wrappers=1:nokey=0 "$p" 2>/dev/null || true; ' + 'fi']
    videoMetaProcess.running = true
  }

  /** 解析 ffprobe / stat 输出为元数据对象 */
  function parseVideoMetaData(data, path) {
    var meta = ({
        path: path,
        name: path.split("/").pop()
      })
    var lines = String(data || "").split(/\r?\n/)
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      var eq = line.indexOf("=")
      if (eq <= 0)
        continue
      var key = line.substring(0, eq)
      var value = line.substring(eq + 1).trim()
      if (value && value !== "N/A")
        meta[key] = value
    }
    return meta
  }

  // ============ 过滤与排序 ============

  /** 按关键词（直接子串优先，其次模糊匹配）与标签过滤、排序 filteredItems */
  function filterItems() {
    var parsed = Logic.parseSearchQuery(searchText)
    var keyword = parsed.keyword
    var requiredTags = Logic.mergeFilterTags(activeTagFilters, parsed.tags)
    var hasKeyword = keyword.length > 0

    // 置顶项恒在最前（按置顶顺序，同样参与搜索/标签过滤）
    var pinnedResults = []
    for (var pi = 0; pi < pinnedItems.length; pi++) {
      var pit = pinnedItems[pi]
      if (!Logic.hasAllTags(pit, requiredTags))
        continue
      if (hasKeyword) {
        var pt = pit.searchBlobLower || ""
        if (pt.indexOf(keyword) === -1 && !Fuzzy.matchLower(keyword, pt).match)
          continue
      }
      pinnedResults.push(pit)
    }

    // 活动条目（排除已置顶 id，避免重复）
    var liveResults = []
    if (!hasKeyword && requiredTags.length === 0) {
      for (var k = 0; k < clipboardItems.length; k++) {
        if (pinnedIdSet[String(clipboardItems[k].id)])
          continue
        liveResults.push(clipboardItems[k])
      }
    } else {
      var results = []
      for (var i = 0; i < clipboardItems.length; i++) {
        var item = clipboardItems[i]
        if (pinnedIdSet[String(item.id)])
          continue
        if (!Logic.hasAllTags(item, requiredTags))
          continue
        if (!hasKeyword) {
          results.push({ item: item, score: 0, originalIndex: i })
          continue
        }

        var searchTarget = item.searchBlobLower || ""
        var directIdx = searchTarget.indexOf(keyword)
        if (directIdx !== -1) {
          results.push({ item: item, score: 2000 - directIdx, originalIndex: i })
          continue
        }

        var m = Fuzzy.matchLower(keyword, searchTarget)
        if (m.match)
          results.push({ item: item, score: m.score, originalIndex: i })
      }

      if (hasKeyword) {
        results.sort(function (a, b) {
          if (b.score !== a.score)
            return b.score - a.score
          return a.originalIndex - b.originalIndex
        })
      }

      liveResults = results.map(function (r) {
        return r.item
      })
    }

    filteredItems = pinnedResults.concat(liveResults)
    if (filteredItems.length === 0) {
      selectedIndex = 0
    } else if (selectedIndex >= filteredItems.length || selectedIndex < 0) {
      selectedIndex = 0
    }
  }

  // ============ 定时器 ============
  Timer {
    id: searchDebounce
    interval: 120
    repeat: false
    onTriggered: {
      if (!root.closing)
        root.filterItems()
    }
  }

  Timer {
    id: loadStartTimer
    interval: 30
    repeat: false
    onTriggered: {
      if (!root.closing) {
        root.loading = true
        root.parsing = false
        root.searchIndexing = false
        root.searchIndexedCount = 0
        root.clipboardBuffer = ""
        loadClipboard.running = true
      }
    }
  }

  Timer {
    id: parseRestTimer
    interval: 1
    repeat: false
    onTriggered: {
      if (!root.closing)
        root.parseRemainingEntries()
    }
  }

  Timer {
    id: decodeChunkTimer
    interval: 60
    repeat: false
    onTriggered: {
      if (!root.closing)
        root.runNextDecodeChunk()
    }
  }

  Timer {
    id: mimeProbeStartTimer
    interval: 260
    repeat: false
    onTriggered: {
      if (!root.closing)
        root.queueMimeProbe()
    }
  }

  Timer {
    id: imageDecodeStartTimer
    interval: 360
    repeat: false
    onTriggered: {
      if (!root.closing)
        root.startImageDecode()
    }
  }

  Timer {
    id: videoThumbStartTimer
    interval: 520
    repeat: false
    onTriggered: {
      if (!root.closing)
        root.startVideoThumbGen()
    }
  }

  onSearchTextChanged: {
    if (!root.closing)
      searchDebounce.restart()
  }
  onPreviewFullTextChanged: {
    if (!root.closing && root.previewVisible && root.previewItem && root.previewItem.isFile && root.previewItem.fileType === "video") {
      root.startVideoMetaProbe(root.previewVideoPath())
    }
  }
  onActiveTagFiltersChanged: {
    if (!root.closing)
      filterItems()
  }

  // ============ 动作进程 ============
  Process {
    id: copyProcess
    command: ["echo"]
    onExited: code => {
      if (code !== 0) {
        console.error("clipboard re-activate failed, exit code:", code)
      }
    }
  }

  Process {
    id: deleteProcess
    command: ["echo"]
  }

  Process {
    id: openFileProcess
    command: ["echo"]
  }

  Process {
    id: saveImageProcess
    property string targetPath: ""
    command: ["echo"]
    onExited: code => {
      root.saveImageRunning = false
      root.saveImageStatus = code === 0 && targetPath ? ("已保存: " + targetPath) : "保存失败"
    }
  }

  Process {
    id: clearProcess
    command: ["bash", "-c", "cliphist wipe && rm -rf '" + cacheDir + "'"]
  }

  Process {
    id: getFullText
    property string targetId: ""
    command: ["bash", "-c", "echo"]
    stdout: SplitParser {
      splitMarker: ""
      onRead: data => {
        root.previewFullText = data
      }
    }
  }

  // ============ 预览 ============

  /** 打开条目预览：拉取全文 / 视频元数据 */
  function showPreview(item) {
    previewItem = item
    previewVisible = true
    previewFullText = ""
    saveImageStatus = ""
    // 置顶项用持久化快照，不走 cliphist decode
    if (item.pinned) {
      if (item.isFile && item.fileType === "video" && item.filePaths.length > 0)
        startVideoMetaProbe(item.filePaths[0])
      if (!item.isImage)
        previewFullText = item.copyText || item.preview || ""
      return
    }
    if (item.isFile && item.fileType === "video" && item.filePaths.length > 0) {
      startVideoMetaProbe(item.filePaths[0])
    }
    if (item.isFile) {
      getFullText.targetId = item.id
      getFullText.command = ["bash", "-c", "cliphist decode '" + item.id + "'"]
      getFullText.running = true
    } else if (!item.isImage) {
      getFullText.targetId = item.id
      getFullText.command = ["bash", "-c", "cliphist decode '" + item.id + "'"]
      getFullText.running = true
    }
  }

  /** 关闭预览 */
  function hidePreview() {
    previewVisible = false
    previewItem = null
    previewFullText = ""
    saveImageStatus = ""
    saveImageRunning = false
  }

  /** 取当前预览视频的本地路径 */
  function previewVideoPath() {
    if (!previewItem || !previewItem.isFile || previewItem.fileType !== "video")
      return ""
    var paths = previewFilePaths && previewFilePaths.length > 0 ? previewFilePaths : previewItem.filePaths
    if (!paths || paths.length === 0)
      return ""
    return Logic.normalizeLocalPath(paths[0])
  }

  /** 把预览中的图片另存到 ~/Pictures/Clipboard/ */
  function savePreviewImageToDisk() {
    if (!previewItem || !previewItem.isImage || saveImageRunning)
      return
    var ext = String(previewItem.imageExt || "png").toLowerCase()
    if (!ext || !/^[a-z0-9]+$/.test(ext))
      ext = "png"
    var targetName = "clipboard-" + Qt.formatDateTime(new Date(), "yyyyMMdd-hhmmss") + "-" + previewItem.id + "." + ext
    saveImageProcess.targetPath = "Pictures/Clipboard/" + targetName
    saveImageStatus = "保存中..."
    saveImageRunning = true
    saveImageProcess.command = ["bash", "-c", 'PIC_DIR="$(xdg-user-dir PICTURES 2>/dev/null || true)"; ' + '[ -n "$PIC_DIR" ] || PIC_DIR="$HOME/Pictures"; ' + 'OUT="$PIC_DIR/Clipboard/' + targetName + '"; ' + 'mkdir -p "$(dirname "$OUT")" && ' + 'cliphist decode ' + Logic.shellQuote(previewItem.id) + ' > "$OUT" && ' + 'test -s "$OUT"']
    saveImageProcess.running = true
  }

  /** 用 xdg-open 打开预览中的视频 */
  function openPreviewVideo() {
    var path = previewVideoPath()
    if (!path)
      return
    openFileProcess.command = ["bash", "-c", "xdg-open " + Logic.shellQuote(path) + " >/dev/null 2>&1 &"]
    openFileProcess.running = true
  }

  // ============ 关闭与清理 ============

  /** 停止所有后台定时器 / 进程缓冲，复位状态（窗口关闭时调用） */
  function stopBackgroundWork() {
    loadStartTimer.running = false
    searchDebounce.running = false
    parseRestTimer.running = false
    decodeChunkTimer.running = false
    mimeProbeStartTimer.running = false
    imageDecodeStartTimer.running = false
    videoThumbStartTimer.running = false

    loading = false
    parsing = false
    searchIndexing = false
    searchIndexedCount = 0
    clipboardBuffer = ""
    asyncDecodeBuffer = ""
    mimeProbeBuffer = ""
    mimeProbePending = false
    videoMetaBuffer = ""
    videoMetaPendingPath = ""
    pendingParseEntries = []
    parseItemsBuffer = []
    parseSeen = ({})
    pendingDecodeIds = []
    pendingDecodeCursor = 0
    imageQueue = []
    imageIndex = 0
    videoQueue = []
    videoIndex = 0
    videoThumbPending = false
    mimeProbeTasks = ({})
  }

  /** 标记进入关闭流程并停止后台工作 */
  function beginClose() {
    if (root.closing)
      return
    root.closing = true
    root.stopBackgroundWork()
  }

  /** 把复制进程改为 setsid 脱离运行（防止随本进程退出而被杀） */
  function startCopyProcessDetached() {
    var command = copyProcess.command
    if (command && command.length >= 3 && command[0] === "bash" && command[1] === "-c") {
      copyProcess.command = ["bash", "-c", "setsid bash -c " + Logic.shellQuote(command[2]) + " >/dev/null 2>&1 &"]
    }
    copyProcess.running = true
  }

  // ============ 二次激活（复制回剪贴板） ============
  // 1. 在 wl-copy 之前先算 hash，规避同步守护进程的竞态
  // 2. 双剪贴板：wl-copy（Wayland）+ xclip（X11），保留原始 MIME 类型
  function selectItem(item) {
    // 置顶项走持久化快照复制
    if (item.pinned) {
      selectPinnedItem(item)
      return
    }
    var x11Helper = 'xclip_try(){ ' + 'if [ -n "${DISPLAY:-}" ]; then xclip "$@" 2>/dev/null && return 0; fi; ' + 'for d in :0 :1 :2 :3; do DISPLAY="$d" xclip "$@" 2>/dev/null && return 0; done; ' + 'return 1; }; ' + 'prefer_uri_for_image(){ local p="$1"; local mode="${QS_IMAGE_FILE_MODE:-auto}"; ' + 'case "$mode" in ' + 'uri) return 0 ;; ' + 'image) return 1 ;; ' + 'esac; ' + 'case "$p" in ' + '*/.config/QQ/*/nt_data/Pic/*/Thumb/*|*/.config/QQ/*/nt_data/Pic/*/Thumb/*.*) return 0 ;; ' + 'esac; ' + 'return 1; }; ' + 'x11_set_file(){ local f="$1"; shift; xclip_try "$@" -i < "$f" || return 1; sleep 0.06; xclip_try "$@" -i < "$f" || true; }; '
    if (item.isFile) {
      copyProcess.command = ["bash", "-c", x11Helper + 'HF_DIR="${XDG_RUNTIME_DIR:-/tmp}/clipboard-sync"; mkdir -p "$HF_DIR" 2>/dev/null || true; HF="$HF_DIR/last_hash"; ' + 'tmp=$(mktemp); tmp_uris=$(mktemp); ' + 'cleanup(){ rm -f "$tmp" "$tmp_uris"; }; ' + 'if ! cliphist decode \'' + item.id + '\' > "$tmp" 2>/dev/null || [ ! -s "$tmp" ]; then cleanup; exit 1; fi; ' + 'while IFS= read -r line || [ -n "$line" ]; do ' + 'line="${line%$\'\\r\'}"; ' + '[ -z "$line" ] && continue; ' + 'if [[ "$line" == copy\\ * ]]; then line="${line#copy }"; fi; ' + 'if [[ "$line" == cut\\ * ]]; then line="${line#cut }"; fi; ' + '[ "$line" = "copy" ] && continue; ' + '[ "$line" = "cut" ] && continue; ' + 'for token in $line; do ' + '[ -z "$token" ] && continue; ' + 'if [[ "$token" == /* ]]; then printf "file://%s\\n" "$token"; else printf "%s\\n" "$token"; fi; ' + 'done; ' + 'done < "$tmp" > "$tmp_uris"; ' + 'if [ ! -s "$tmp_uris" ]; then cleanup; exit 1; fi; ' + 'first=$(sed -n "1p" "$tmp_uris"); second=$(sed -n "2p" "$tmp_uris"); ' + 'path=""; ' + 'if [ -n "$first" ] && [ -z "$second" ]; then ' + 'case "$first" in file://localhost/*) path="/${first#file://localhost/}" ;; file:///*) path="${first#file://}" ;; /*) path="$first" ;; esac; ' + 'fi; ' + 'if [ -n "$path" ] && [ -f "$path" ]; then ' + 'mime=$(file -Lb --mime-type -- "$path" 2>/dev/null || true); ' + 'if [[ "$mime" == image/* ]] && [ "$mime" != "image/gif" ] && ! prefer_uri_for_image "$path"; then ' + 'sha256sum "$path" 2>/dev/null | cut -d" " -f1 > "$HF" 2>/dev/null; ' + 'wl-copy --type "$mime" < "$path"; ' + 'x11_set_file "$path" -selection clipboard -t "$mime"; ' + 'cleanup; exit 0; ' + 'fi; ' + 'fi; ' + 'sha256sum "$tmp_uris" 2>/dev/null | cut -d" " -f1 > "$HF" 2>/dev/null; ' + 'wl-copy --type text/uri-list < "$tmp_uris"; ' + 'x11_set_file "$tmp_uris" -selection clipboard -t text/uri-list; ' + 'cleanup; exit 0']
    } else if (item.isImage) {
      var cacheImagePath = imagePathById(item.id)
      copyProcess.command = ["bash", "-c", x11Helper + 'HF_DIR="${XDG_RUNTIME_DIR:-/tmp}/clipboard-sync"; mkdir -p "$HF_DIR" 2>/dev/null || true; HF="$HF_DIR/last_hash"; ' + 'tmp=$(mktemp); status=1; ' + 'copy_image(){ local src="$1"; local mime; mime=$(file -b --mime-type "$src" 2>/dev/null || true); ' + 'if [[ "$mime" != image/* ]]; then return 1; fi; ' + 'if [ "$mime" = "image/png" ]; then ' + 'sha256sum "$src" 2>/dev/null | cut -d" " -f1 > "$HF" 2>/dev/null; ' + 'wl-copy --type image/png < "$src"; x11_set_file "$src" -selection clipboard -t image/png; return 0; fi; ' + 'if [ "$mime" = "image/gif" ]; then ' + 'sha256sum "$src" 2>/dev/null | cut -d" " -f1 > "$HF" 2>/dev/null; ' + 'wl-copy --type image/gif < "$src"; ' + 'x11_set_file "$src" -selection clipboard -t image/gif; return 0; fi; ' + 'sha256sum "$src" 2>/dev/null | cut -d" " -f1 > "$HF" 2>/dev/null; ' + 'wl-copy --type "$mime" < "$src"; x11_set_file "$src" -selection clipboard -t "$mime"; return 0; }; ' + 'if cliphist decode "' + item.id + '" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then copy_image "$tmp"; status=$?; fi; ' + 'rm -f "$tmp"; ' + 'if [ $status -ne 0 ]; then ' + 'for c in "' + cacheImagePath + '" "' + cacheDir + '/' + item.id + '.png" "' + cacheDir + '/' + item.id + '.gif" "' + cacheDir + '/' + item.id + '.jpeg" "' + cacheDir + '/' + item.id + '.jpg" "' + cacheDir + '/' + item.id + '.webp"; do ' + 'if [ -s "$c" ]; then copy_image "$c"; status=$?; [ $status -eq 0 ] && break; fi; ' + 'done; ' + 'fi; ' + 'exit $status']
    } else {
      var htmlLocalPath = ""
      if (item.textType === "html" && item.htmlImageSrcs && item.htmlImageSrcs.length > 0) {
        htmlLocalPath = Logic.normalizeLocalPath(item.htmlImageSrcs[0])
        if (!htmlLocalPath || htmlLocalPath.charAt(0) !== "/")
          htmlLocalPath = ""
      }

      if (htmlLocalPath) {
        copyProcess.command = ["bash", "-c", x11Helper + 'HF_DIR="${XDG_RUNTIME_DIR:-/tmp}/clipboard-sync"; mkdir -p "$HF_DIR" 2>/dev/null || true; HF="$HF_DIR/last_hash"; ' + 'tmp_uris=$(mktemp); cleanup(){ rm -f "$tmp_uris"; }; ' + 'path=' + Logic.shellQuote(htmlLocalPath) + '; ' + 'mime=$(file -Lb --mime-type -- "$path" 2>/dev/null || true); ' + 'if [[ "$mime" == image/* ]] && [ "$mime" != "image/gif" ] && ! prefer_uri_for_image "$path"; then ' + 'sha256sum "$path" 2>/dev/null | cut -d" " -f1 > "$HF" 2>/dev/null; ' + 'wl-copy --type "$mime" < "$path"; ' + 'x11_set_file "$path" -selection clipboard -t "$mime"; ' + 'cleanup; exit 0; ' + 'fi; ' + 'printf "file://%s\\n" "$path" > "$tmp_uris"; ' + 'sha256sum "$tmp_uris" 2>/dev/null | cut -d" " -f1 > "$HF" 2>/dev/null; ' + 'wl-copy --type text/uri-list < "$tmp_uris"; ' + 'x11_set_file "$tmp_uris" -selection clipboard -t text/uri-list; ' + 'cleanup; exit 0']
      } else if (item.textType === "html" && item.htmlPreferPlain && item.htmlPlainText && item.htmlPlainText.length > 0) {
        copyProcess.command = ["bash", "-c", x11Helper + 'HF_DIR="${XDG_RUNTIME_DIR:-/tmp}/clipboard-sync"; mkdir -p "$HF_DIR" 2>/dev/null || true; HF="$HF_DIR/last_hash"; ' + 'tmp=$(mktemp); ' + 'printf "%s" ' + Logic.shellQuote(item.htmlPlainText) + ' > "$tmp"; ' + 'sha256sum "$tmp" 2>/dev/null | cut -d" " -f1 > "$HF" 2>/dev/null; ' + 'wl-copy --type \'text/plain;charset=utf-8\' < "$tmp"; ' + 'x11_set_file "$tmp" -selection clipboard -t UTF8_STRING || x11_set_file "$tmp" -selection clipboard -t text/plain; ' + 'rm -f "$tmp"']
      } else {
        var mimeFlag = item.textType === "html" ? '--type text/html ' : ''
        var xclipTypeFlag = '-t UTF8_STRING '
        copyProcess.command = ["bash", "-c", x11Helper + 'HF_DIR="${XDG_RUNTIME_DIR:-/tmp}/clipboard-sync"; mkdir -p "$HF_DIR" 2>/dev/null || true; HF="$HF_DIR/last_hash"; ' + 'tmp=$(mktemp); ' + 'cliphist decode \'' + item.id + '\' > "$tmp" 2>/dev/null; ' + 'sha256sum "$tmp" 2>/dev/null | cut -d" " -f1 > "$HF" 2>/dev/null; ' + 'wl-copy ' + mimeFlag + '< "$tmp"; ' + 'x11_set_file "$tmp" -selection clipboard ' + xclipTypeFlag + ' || x11_set_file "$tmp" -selection clipboard -t text/plain; ' + 'rm -f "$tmp"']
      }
    }
    startCopyProcessDetached()
    closeRequested()
  }

  /** 删除某条目（置顶项 → 取消置顶；普通项 → cliphist delete + 本地移除） */
  function deleteItem(item) {
    if (item.pinned) {
      unpinItem(item)
      return
    }
    deleteProcess.command = ["bash", "-c", "cliphist list | grep -m1 '^" + item.id + "\t' | cliphist delete"]
    deleteProcess.running = true
    clipboardItems = clipboardItems.filter(i => i.id !== item.id)
    parseItemsBuffer = parseItemsBuffer.filter(i => i.id !== item.id)
    pendingParseEntries = pendingParseEntries.filter(i => i.id !== item.id)
    pendingDecodeIds = pendingDecodeIds.filter(id => String(id) !== String(item.id))
    rebuildItemIndexMap()
    rebuildTagCounts()
    filterItems()
  }

  /** 清空全部剪贴板（cliphist wipe + 清缓存目录） */
  function clearAll() {
    clearProcess.running = true
    clipboardItems = []
    itemIndexById = ({})
    tagCounts = ({})
    pendingDecodeIds = []
    pendingDecodeCursor = 0
    pendingParseEntries = []
    parseItemsBuffer = []
    parseSeen = ({})
    loading = false
    parsing = false
    searchIndexing = false
    searchIndexedCount = 0
    parseRestTimer.running = false
    decodeChunkTimer.running = false
    mimeProbeStartTimer.running = false
    imageDecodeStartTimer.running = false
    videoThumbStartTimer.running = false
    // 置顶项是独立持久化的，不随清空丢失；但顺手回收孤儿快照
    gcOrphanPins()
    filterItems()
  }

  /** 选中当前高亮条目并复制 */
  function selectCurrent() {
    if (filteredItems.length > 0 && selectedIndex < filteredItems.length) {
      selectItem(filteredItems[selectedIndex])
    }
  }

  // ============ 置顶持久化与增删 ============
  property string pinBuffer: ""

  // 读取磁盘上的置顶清单
  Process {
    id: loadPinsProc
    command: ["bash", "-c", "cat " + Logic.shellQuote(root.pinFile) + " 2>/dev/null || true"]
    stdout: SplitParser {
      splitMarker: ""
      onRead: data => {
        root.pinBuffer += data
      }
    }
    onExited: code => {
      root.applyLoadedPins(root.pinBuffer)
      root.pinBuffer = ""
    }
  }

  // 写回置顶清单
  Process {
    id: savePinsProc
    command: ["echo"]
  }

  // 回收孤儿快照（pins 目录里 pins.json 已不再引用的图片文件）
  Process {
    id: gcPinsProc
    command: ["echo"]
  }

  /** 清理 pins 目录下未被任何置顶项引用的快照文件 */
  function gcOrphanPins() {
    var keep = []
    for (var i = 0; i < pinnedItems.length; i++) {
      var it = pinnedItems[i]
      if (it.isImage && it.imageFile)
        keep.push(it.imageFile.split("/").pop())
    }
    var keepList = keep.join("\n")
    gcPinsProc.command = ["bash", "-c", 'd=' + Logic.shellQuote(pinDir) + '; [ -d "$d" ] || exit 0; ' + 'keep=' + Logic.shellQuote(keepList) + '; ' + 'for f in "$d"/*; do [ -e "$f" ] || continue; bn=$(basename -- "$f"); ' + '[ "$bn" = "pins.json" ] && continue; ' + 'printf "%s\\n" "$keep" | grep -qxF -- "$bn" || rm -f -- "$f"; done']
    gcPinsProc.running = true
  }

  // 置顶时抓取内容快照（图片落盘 / 文本解码）
  Process {
    id: pinSnapshotProc
    property var pendingItem: null
    property string snapshotFile: ""
    property string buffer: ""
    command: ["echo"]
    stdout: SplitParser {
      splitMarker: ""
      onRead: data => {
        pinSnapshotProc.buffer += data
      }
    }
    onExited: code => {
      root.finishPin(pinSnapshotProc.pendingItem, code, pinSnapshotProc.buffer, pinSnapshotProc.snapshotFile)
      pinSnapshotProc.pendingItem = null
      pinSnapshotProc.snapshotFile = ""
      pinSnapshotProc.buffer = ""
    }
  }

  /** 条目是否已置顶 */
  function isPinned(item) {
    return item && !!pinnedIdSet[String(item.id)]
  }

  /** 启动时载入持久化的置顶项 */
  function loadPins() {
    root.pinBuffer = ""
    loadPinsProc.running = true
  }

  /** 解析载入的置顶 JSON，重建条目派生字段并刷新列表 */
  function applyLoadedPins(jsonText) {
    var arr = []
    try {
      var parsed = JSON.parse(String(jsonText || "").trim() || "[]")
      if (Array.isArray(parsed))
        arr = parsed
    } catch (e) {
      arr = []
    }
    var set = {}
    var imgPaths = Object.assign({}, root.imagePaths)
    for (var i = 0; i < arr.length; i++) {
      var it = arr[i]
      it.pinned = true
      if (it.copyText)
        it.decodedSearchLower = String(it.copyText).toLowerCase()
      root.rebuildItemDerivedFields(it)
      set[String(it.id)] = true
      if (it.isImage && it.imageFile)
        imgPaths[String(it.id)] = it.imageFile
    }
    root.pinnedItems = arr
    root.pinnedIdSet = set
    root.imagePaths = imgPaths
    gcOrphanPins()  // 顺便清理历史遗留的孤儿快照
    if (!root.closing)
      root.filterItems()
  }

  /** 持久化置顶项到磁盘 */
  function savePins() {
    var json = JSON.stringify(root.pinnedItems.map(function (it) {
      return {
        id: it.id, isImage: it.isImage, imageExt: it.imageExt,
        imageDimensions: it.imageDimensions, imageSize: it.imageSize,
        isFile: it.isFile, fileType: it.fileType, fileMime: it.fileMime, filePaths: it.filePaths,
        textType: it.textType, htmlImageSrcs: it.htmlImageSrcs, htmlImageMime: it.htmlImageMime,
        htmlPlainText: it.htmlPlainText, htmlPreferPlain: it.htmlPreferPlain,
        rawContent: it.rawContent, preview: it.preview, colorValue: it.colorValue,
        copyText: it.copyText || "", copyMime: it.copyMime || "",
        imageFile: it.imageFile || "", imageMime: it.imageMime || ""
      }
    }))
    savePinsProc.command = ["bash", "-c", "mkdir -p " + Logic.shellQuote(pinDir) + "; printf '%s' " + Logic.shellQuote(json) + " > " + Logic.shellQuote(pinFile)]
    savePinsProc.running = true
  }

  /** 置顶一个条目（异步抓取快照后入库） */
  function pinItem(item) {
    if (!item || isPinned(item) || pinSnapshotProc.running)
      return
    pinSnapshotProc.pendingItem = item
    pinSnapshotProc.buffer = ""
    if (item.isImage) {
      var ext = String(item.imageExt || "png").toLowerCase().replace(/[^a-z0-9]/g, "") || "png"
      var snap = pinDir + "/" + item.id + "." + ext
      pinSnapshotProc.snapshotFile = snap
      pinSnapshotProc.command = ["bash", "-c", "mkdir -p " + Logic.shellQuote(pinDir) + "; cliphist decode " + Logic.shellQuote(String(item.id)) + " > " + Logic.shellQuote(snap) + " 2>/dev/null && file -Lb --mime-type -- " + Logic.shellQuote(snap) + " 2>/dev/null || true"]
    } else if (item.isFile) {
      pinSnapshotProc.snapshotFile = ""
      pinSnapshotProc.command = ["bash", "-c", "true"]
    } else {
      pinSnapshotProc.snapshotFile = ""
      pinSnapshotProc.command = ["bash", "-c", "cliphist decode " + Logic.shellQuote(String(item.id)) + " 2>/dev/null || true"]
    }
    pinSnapshotProc.running = true
  }

  /** 快照抓取完成后构造置顶记录入库 */
  function finishPin(item, code, output, snapshotFile) {
    if (!item || root.closing)
      return
    var rec = JSON.parse(JSON.stringify(item))
    rec.pinned = true
    if (item.isImage) {
      rec.imageFile = snapshotFile
      rec.imageMime = String(output || "").trim().split(/\s+/)[0] || ("image/" + (item.imageExt || "png"))
      rec.copyText = ""
      rec.copyMime = ""
    } else if (item.isFile) {
      rec.copyText = (item.filePaths || []).map(function (p) {
        return "file://" + p
      }).join("\n")
      rec.copyMime = "text/uri-list"
    } else {
      rec.copyText = (item.textType === "html" && item.htmlPreferPlain && item.htmlPlainText) ? item.htmlPlainText : String(output || "")
      rec.copyMime = (item.textType === "html" && !item.htmlPreferPlain) ? "text/html" : "text/plain"
    }
    rec.decodedSearchLower = String(rec.copyText || "").toLowerCase()
    rebuildItemDerivedFields(rec)

    var next = root.pinnedItems.slice()
    next.unshift(rec)
    root.pinnedItems = next
    var set = Object.assign({}, root.pinnedIdSet)
    set[String(rec.id)] = true
    root.pinnedIdSet = set
    if (rec.isImage && rec.imageFile) {
      var ip = Object.assign({}, root.imagePaths)
      ip[String(rec.id)] = rec.imageFile
      root.imagePaths = ip
    }
    savePins()
    filterItems()
  }

  /** 取消置顶 */
  function unpinItem(item) {
    if (!item)
      return
    var id = String(item.id)
    root.pinnedItems = root.pinnedItems.filter(function (p) {
      return String(p.id) !== id
    })
    var set = Object.assign({}, root.pinnedIdSet)
    delete set[id]
    root.pinnedIdSet = set
    savePins()
    gcOrphanPins()
    filterItems()
  }

  /** 切换置顶状态 */
  function togglePin(item) {
    if (isPinned(item))
      unpinItem(item)
    else
      pinItem(item)
  }

  /** 复制置顶项（用持久化快照，不依赖 cliphist 条目是否还在） */
  function selectPinnedItem(item) {
    var hashPrefix = 'HF_DIR="${XDG_RUNTIME_DIR:-/tmp}/clipboard-sync"; mkdir -p "$HF_DIR" 2>/dev/null || true; HF="$HF_DIR/last_hash"; '
    if (item.isImage && item.imageFile) {
      var imime = item.imageMime || ("image/" + (item.imageExt || "png"))
      copyProcess.command = ["bash", "-c", hashPrefix + 'src=' + Logic.shellQuote(item.imageFile) + '; [ -s "$src" ] || exit 1; ' + 'sha256sum "$src" 2>/dev/null | cut -d" " -f1 > "$HF" 2>/dev/null; ' + 'wl-copy --type ' + Logic.shellQuote(imime) + ' < "$src"; ' + 'if command -v xclip >/dev/null 2>&1; then xclip -selection clipboard -t ' + Logic.shellQuote(imime) + ' -i < "$src" 2>/dev/null || true; fi']
    } else {
      var mime = item.copyMime || "text/plain"
      copyProcess.command = ["bash", "-c", hashPrefix + 'tmp=$(mktemp); printf "%s" ' + Logic.shellQuote(item.copyText || "") + ' > "$tmp"; ' + 'sha256sum "$tmp" 2>/dev/null | cut -d" " -f1 > "$HF" 2>/dev/null; ' + 'wl-copy --type ' + Logic.shellQuote(mime) + ' < "$tmp"; ' + 'if command -v xclip >/dev/null 2>&1; then xclip -selection clipboard -i < "$tmp" 2>/dev/null || true; fi; rm -f "$tmp"']
    }
    startCopyProcessDetached()
    closeRequested()
  }

  // 启动：延迟一帧开始加载，避免阻塞首次渲染；同时载入置顶项
  Component.onCompleted: {
    loadPins()
    loadStartTimer.restart()
  }
}
