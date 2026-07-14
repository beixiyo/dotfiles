// ClipboardLogic.js — 剪贴板纯函数逻辑库（无状态）
//
// 这里只放「输入 → 输出」的纯函数：cliphist 文本清洗、类型分类、颜色解析、HTML 解析、
// 文件路径提取、二进制元数据解析等。所有函数都不依赖任何 QML 对象 / 运行时状态
// （mime 缓存、Theme、Process 等都留在 ClipboardController.qml）。
//
// 标记为 .pragma library：多个 QML 文档导入时共享同一份，省内存。该上下文仍可访问
// Qt 全局对象（如 Qt.rgba），但访问不到导入方的 QML 实例与属性。
//
// 注意：涉及控制字符的正则一律用 \uXXXX 转义书写，避免源码里出现不可见字节。
.pragma library

// ============ 静态分类表 ============

/** 标签别名归一化表：各种中英文写法 → 规范标签 id */
const TAG_ALIAS_MAP = {
  "text": "text", "文本": "text",
  "code": "code", "代码": "code",
  "url": "url", "链接": "url", "link": "url",
  "path": "path", "路径": "path",
  "image": "image", "img": "image", "图片": "image", "图像": "image",
  "gif": "gif",
  "video": "video", "视频": "video",
  "audio": "audio", "音频": "audio",
  "file": "file", "文件": "file",
  "document": "document", "doc": "document", "文档": "document",
  "archive": "archive", "压缩包": "archive", "压缩": "archive",
  "html": "html", "网页": "html",
  "color": "color", "颜色": "color"
}

/** 各类文件的扩展名集合（用于无 mime 时的兜底分类，以及预览图标选择） */
const imageExts = ["png", "jpg", "jpeg", "webp", "bmp", "tiff", "tif", "ico", "svg"]
const gifExts = ["gif"]
const videoExts = ["mp4", "mkv", "webm", "avi", "mov", "flv", "wmv", "m4v", "ts", "mpg", "mpeg"]
const audioExts = ["mp3", "flac", "wav", "ogg", "m4a", "aac", "wma", "opus"]
const archiveExts = ["zip", "tar", "gz", "bz2", "xz", "7z", "rar", "zst"]
const docExts = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp", "txt", "md", "csv"]

// ============ 控制字符常量 ============
// 用 String.fromCharCode 构造，保证源码文件全程为纯 ASCII、不含任何不可见字节
const CHAR_NUL = String.fromCharCode(0)        // U+0000 空字符
const CHAR_CR = String.fromCharCode(13)        // U+000D 回车符
const CHAR_SUB = String.fromCharCode(0x1A)     // U+001A 替换字符（SUB）
const CHAR_NBSP = String.fromCharCode(0xA0)    // U+00A0 不换行空格
const CHAR_REPLACEMENT = String.fromCharCode(0xFFFD) // U+FFFD 解码失败占位符
// 匹配 [U+0000-U+001F] 与 U+007F 的控制字符正则
const CTRL_CHARS_RE = new RegExp("[" + CHAR_NUL + "-" + String.fromCharCode(0x1F) + String.fromCharCode(0x7F) + "]", "g")

// ============ 通用字符串处理 ============

/**
 * 把字符串安全地包成 shell 单引号参数，转义内部单引号。
 * @param {string} str 原始字符串
 * @returns {string} 形如 'xxx' 的可直接拼进 bash 命令的片段
 */
function shellQuote(str) {
  return "'" + String(str === undefined || str === null ? "" : str).replace(/'/g, "'\"'\"'") + "'"
}

/**
 * 把各种 file:// 形式的 URI 规范化为本地绝对路径，并做 URL 解码。
 * @param {string} path 原始路径或 file:// URI
 * @returns {string} 本地绝对路径；无法识别时尽量返回去前缀后的字符串
 */
function normalizeLocalPath(path) {
  let p = String(path === undefined || path === null ? "" : path)
  if (!p)
    return ""
  if (p.startsWith("file://localhost/")) {
    p = "/" + p.substring("file://localhost/".length)
  } else if (p.startsWith("file:///")) {
    p = p.substring("file://".length)
  } else if (p.startsWith("file://")) {
    p = p.substring("file://".length)
  }
  try {
    p = decodeURIComponent(p)
  } catch (e) {}
  return p
}

/**
 * 清洗剪贴板文本：剔除空字符（NUL）与回车符（\r）。
 * @param {string} text 原始文本
 * @returns {string} 清洗后的文本
 */
function sanitizeClipboardText(text) {
  let s = String(text === undefined || text === null ? "" : text)
  s = s.split(CHAR_NUL).join("")
  s = s.split(CHAR_CR).join("")
  return s
}

/**
 * 生成列表卡片用的单行预览文本（截断、压平换行、转义尖括号）。
 * @param {string} text 原始文本
 * @returns {string} 最多 200 字符的安全预览串
 */
function previewText(text) {
  return sanitizeClipboardText(text).substring(0, 200).replace(/\n/g, " ").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

/**
 * 向数组追加一个去重后的非空值（原地修改）。
 * @param {Array} list 目标数组
 * @param {*} value 待追加的值
 */
function pushUnique(list, value) {
  if (!value)
    return
  if (list.indexOf(value) === -1)
    list.push(value)
}

// ============ 标签与搜索 ============

/**
 * 把任意标签写法归一化为规范标签 id。
 * @param {string} tag 原始标签（可带 # 前缀、中英文）
 * @returns {string} 规范标签 id；无效返回空串
 */
function normalizeTag(tag) {
  let normalized = String(tag === undefined || tag === null ? "" : tag).trim().toLowerCase()
  normalized = normalized.replace(/^#+/, "")
  if (!normalized)
    return ""
  return TAG_ALIAS_MAP[normalized] || normalized
}

/**
 * 解析搜索框输入，拆出关键词与 #标签。
 * @param {string} text 搜索框原始文本
 * @returns {{ keyword: string, tags: string[] }} 小写关键词与规范标签数组
 */
function parseSearchQuery(text) {
  const src = String(text === undefined || text === null ? "" : text)
  const tagTokens = src.match(/#([^\s#]+)/g) || []
  const tags = []
  for (let i = 0; i < tagTokens.length; i++) {
    const nextTag = normalizeTag(tagTokens[i].substring(1))
    if (nextTag)
      pushUnique(tags, nextTag)
  }
  const keyword = src.replace(/#([^\s#]+)/g, " ").replace(/\s+/g, " ").trim().toLowerCase()
  return { keyword: keyword, tags: tags }
}

/**
 * 合并「面板已选标签」与「搜索框内联标签」。
 * @param {string[]} activeTags 面板上已激活的标签
 * @param {string[]} searchTags 搜索框里解析出的标签
 * @returns {string[]} 去重合并后的标签数组
 */
function mergeFilterTags(activeTags, searchTags) {
  const merged = (activeTags || []).slice()
  for (let i = 0; i < searchTags.length; i++) {
    pushUnique(merged, searchTags[i])
  }
  return merged
}

/**
 * 判断条目是否满足全部所需标签。
 * @param {object} item 剪贴板条目
 * @param {string[]} requiredTags 所需标签
 * @returns {boolean} 是否全部命中
 */
function hasAllTags(item, requiredTags) {
  if (!requiredTags || requiredTags.length === 0)
    return true
  const set = item.tagSet || {}
  for (let i = 0; i < requiredTags.length; i++) {
    if (!set[requiredTags[i]])
      return false
  }
  return true
}

/**
 * 根据条目内容推导其标签集合（图片/文件/文本及其子类型）。
 * @param {object} item 剪贴板条目
 * @returns {string[]} 标签数组
 */
function buildItemTags(item) {
  const tags = []

  if (item.isImage) {
    pushUnique(tags, "image")
    if (String(item.imageExt || "").toLowerCase() === "gif")
      pushUnique(tags, "gif")
  } else if (item.isFile) {
    pushUnique(tags, "file")
    if (item.fileType)
      pushUnique(tags, item.fileType)
    if (item.filePaths && item.filePaths.length > 1)
      pushUnique(tags, "multi")
  } else {
    pushUnique(tags, "text")
    if (item.textType)
      pushUnique(tags, item.textType)
  }

  if (item.textType === "html" && item.htmlImageSrcs && item.htmlImageSrcs.length > 0) {
    pushUnique(tags, "image")
    pushUnique(tags, "html")
  }

  return tags
}

// ============ 二进制噪声检测 ============

/**
 * 启发式判断一段文本是否其实是二进制噪声（如被当作文本读出的图片数据）。
 * @param {string} content 原始内容
 * @returns {boolean} 是否疑似二进制噪声
 */
function isLikelyBinaryNoiseText(content) {
  const raw = String(content === undefined || content === null ? "" : content)
  if (raw.indexOf(CHAR_NUL) !== -1)
    return true
  const s = sanitizeClipboardText(raw)
  if (!s)
    return false
  let probe = s
  if (probe.startsWith("copy "))
    probe = probe.substring(5)
  if (probe.startsWith("cut "))
    probe = probe.substring(4)

  if (/IHDR/.test(probe) && /IDAT/.test(probe))
    return true
  if (new RegExp("^" + CHAR_SUB + "\\s*" + CHAR_NUL + "{2,}").test(probe))
    return true

  const limit = Math.min(probe.length, 280)
  let ctrl = 0
  let repl = 0
  for (let i = 0; i < limit; i++) {
    const c = probe.charCodeAt(i)
    if (probe.charAt(i) === CHAR_REPLACEMENT)
      repl++
    if (c === 9 || c === 10 || c === 13)
      continue
    if (c < 32 || c === 127)
      ctrl++
  }

  if (repl >= 4 && (probe.indexOf("IHDR") !== -1 || probe.indexOf("IDAT") !== -1))
    return true
  return limit > 24 && (ctrl / limit) > 0.08
}

// ============ 文件类型分类 ============

/**
 * 仅凭扩展名分类文件。
 * @param {string} path 文件路径
 * @returns {string} 类型：gif/image/video/audio/archive/document/other
 */
function classifyFileByExt(path) {
  const ext = path.split(".").pop().toLowerCase()
  if (gifExts.indexOf(ext) !== -1)
    return "gif"
  if (imageExts.indexOf(ext) !== -1)
    return "image"
  if (videoExts.indexOf(ext) !== -1)
    return "video"
  if (audioExts.indexOf(ext) !== -1)
    return "audio"
  if (archiveExts.indexOf(ext) !== -1)
    return "archive"
  if (docExts.indexOf(ext) !== -1)
    return "document"
  return "other"
}

/**
 * 优先按 mime 分类文件，识别不出时回退到扩展名。
 * @param {string} mime MIME 类型，如 "image/png"
 * @param {string} path 文件路径（兜底用）
 * @returns {string} 类型：gif/image/video/audio/archive/document/other
 */
function classifyFileByMime(mime, path) {
  const m = String(mime === undefined || mime === null ? "" : mime).toLowerCase()
  if (m === "image/gif")
    return "gif"
  if (m.startsWith("image/"))
    return "image"
  if (m.startsWith("video/"))
    return "video"
  if (m.startsWith("audio/"))
    return "audio"
  if (m.indexOf("zip") !== -1 || m.indexOf("compressed") !== -1 || m === "application/x-tar")
    return "archive"
  if (m.startsWith("text/") || m === "application/pdf" || m.indexOf("document") !== -1 || m.indexOf("sheet") !== -1 || m.indexOf("presentation") !== -1)
    return "document"
  return classifyFileByExt(path)
}

// ============ 颜色解析 ============

/**
 * 从可能带标签前缀（如 "HEX #fff"）的颜色文本中取出颜色值本体。
 * @param {string} content 颜色文本
 * @returns {string} 颜色值字符串
 */
function colorSourceText(content) {
  const s = sanitizeClipboardText(content).trim()
  const labeled = s.match(/^(?:hex lower|HEX|RGBA|RGB|HSL|HSV|Qt)\s+(.+)$/i)
  return labeled ? String(labeled[1] || "").trim() : s
}

/**
 * 把 0~1 的通道值转成两位十六进制。
 * @param {number} v 0~1
 * @returns {string} 两位十六进制
 */
function hexByte(v) {
  const h = Math.round(v * 255).toString(16)
  return h.length === 1 ? "0" + h : h
}

/**
 * 把 0~1 的 RGBA 单位值转成颜色（不透明时返回 hex 字符串，半透明时返回 Qt.rgba）。
 * @returns {string|color|null} 颜色；越界或非法返回 null
 */
function colorFromRgbUnit(r, g, b, a) {
  if (a === undefined || a === null)
    a = 1
  if (r === null || g === null || b === null || a === null)
    return null
  if (isNaN(r) || isNaN(g) || isNaN(b) || isNaN(a))
    return null
  if (a < 0 || a > 1)
    return null
  if (r < 0 || r > 1 || g < 0 || g > 1 || b < 0 || b > 1)
    return null
  if (a === 1)
    return "#" + hexByte(r) + hexByte(g) + hexByte(b)
  return Qt.rgba(r, g, b, a)
}

/**
 * 解析 CSS rgb() 中的单个通道（支持百分比与 0~255）。
 * @returns {number|null} 0~1 单位值；非法返回 null
 */
function parseCssChannel(value) {
  const s = String(value || "").trim()
  if (!s)
    return null
  const isPercent = s.endsWith("%")
  const n = parseFloat(isPercent ? s.slice(0, -1) : s)
  if (isNaN(n))
    return null
  if (isPercent)
    return n >= 0 && n <= 100 ? n / 100 : null
  return n >= 0 && n <= 255 ? n / 255 : null
}

/**
 * 解析 CSS alpha 通道（支持百分比与 0~1，缺省为 1）。
 * @returns {number|null} 0~1；非法返回 null
 */
function parseCssAlpha(value) {
  if (value === undefined || value === null || String(value).trim() === "")
    return 1
  const s = String(value).trim()
  const isPercent = s.endsWith("%")
  const n = parseFloat(isPercent ? s.slice(0, -1) : s)
  if (isNaN(n))
    return null
  if (isPercent)
    return n >= 0 && n <= 100 ? n / 100 : null
  return n >= 0 && n <= 1 ? n : null
}

/**
 * 归一化色相到 [0, 360)。
 * @returns {number|null} 色相；非法返回 null
 */
function normalizeHue(value) {
  let h = parseFloat(String(value || "").trim())
  if (isNaN(h))
    return null
  h = h % 360
  if (h < 0)
    h += 360
  return h
}

/**
 * 解析百分比单位值（必须带 %）。
 * @returns {number|null} 0~1；非法返回 null
 */
function parsePercentUnit(value) {
  const s = String(value || "").trim()
  if (!s.endsWith("%"))
    return null
  const n = parseFloat(s.slice(0, -1))
  if (isNaN(n) || n < 0 || n > 100)
    return null
  return n / 100
}

/**
 * HSL → 颜色。
 * @returns {string|color|null} 颜色；任一入参为 null 返回 null
 */
function hslToColor(h, s, l, a) {
  if (h === null || s === null || l === null || a === null)
    return null
  const c = (1 - Math.abs(2 * l - 1)) * s
  const x = c * (1 - Math.abs((h / 60) % 2 - 1))
  const m = l - c / 2
  let r = 0, g = 0, b = 0
  if (h < 60) {
    r = c; g = x
  } else if (h < 120) {
    r = x; g = c
  } else if (h < 180) {
    g = c; b = x
  } else if (h < 240) {
    g = x; b = c
  } else if (h < 300) {
    r = x; b = c
  } else {
    r = c; b = x
  }
  return colorFromRgbUnit(r + m, g + m, b + m, a)
}

/**
 * HSV → 颜色。
 * @returns {string|color|null} 颜色；任一入参为 null 返回 null
 */
function hsvToColor(h, s, v, a) {
  if (h === null || s === null || v === null || a === null)
    return null
  const c = v * s
  const x = c * (1 - Math.abs((h / 60) % 2 - 1))
  const m = v - c
  let r = 0, g = 0, b = 0
  if (h < 60) {
    r = c; g = x
  } else if (h < 120) {
    r = x; g = c
  } else if (h < 180) {
    g = c; b = x
  } else if (h < 240) {
    g = x; b = c
  } else if (h < 300) {
    r = x; b = c
  } else {
    r = c; b = x
  }
  return colorFromRgbUnit(r + m, g + m, b + m, a)
}

/**
 * 把各种格式的颜色文本（#hex / rgb(a) / hsl(a) / hsv(a) / Qt.rgba）解析为颜色值。
 * @param {string} content 颜色文本
 * @returns {string|color|null} 颜色；无法解析返回 null
 */
function normalizeColorValue(content) {
  const s = colorSourceText(content)
  let m = s.match(/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/)
  if (m) {
    let hex = m[1]
    if (hex.length === 3 || hex.length === 4) {
      hex = hex.split("").map(c => c + c).join("")
    }
    const r = parseInt(hex.slice(0, 2), 16) / 255
    const g = parseInt(hex.slice(2, 4), 16) / 255
    const b = parseInt(hex.slice(4, 6), 16) / 255
    const a = hex.length === 8 ? parseInt(hex.slice(6, 8), 16) / 255 : 1
    return colorFromRgbUnit(r, g, b, a)
  }

  m = s.match(/^rgba?\((.*)\)$/i)
  if (m) {
    const rgbParts = m[1].split(",")
    if (rgbParts.length === 3 || rgbParts.length === 4) {
      return colorFromRgbUnit(parseCssChannel(rgbParts[0]), parseCssChannel(rgbParts[1]), parseCssChannel(rgbParts[2]), parseCssAlpha(rgbParts[3]))
    }
  }

  m = s.match(/^hsla?\((.*)\)$/i)
  if (m) {
    const hslParts = m[1].split(",")
    if (hslParts.length === 3 || hslParts.length === 4) {
      return hslToColor(normalizeHue(hslParts[0]), parsePercentUnit(hslParts[1]), parsePercentUnit(hslParts[2]), parseCssAlpha(hslParts[3]))
    }
  }

  m = s.match(/^hsva?\((.*)\)$/i)
  if (m) {
    const hsvParts = m[1].split(",")
    if (hsvParts.length === 3 || hsvParts.length === 4) {
      return hsvToColor(normalizeHue(hsvParts[0]), parsePercentUnit(hsvParts[1]), parsePercentUnit(hsvParts[2]), parseCssAlpha(hsvParts[3]))
    }
  }

  m = s.match(/^Qt\.rgba\((.*)\)$/i)
  if (m) {
    const qtParts = m[1].split(",")
    if (qtParts.length === 4) {
      const qr = parseFloat(qtParts[0])
      const qg = parseFloat(qtParts[1])
      const qb = parseFloat(qtParts[2])
      const qa = parseFloat(qtParts[3])
      return colorFromRgbUnit(qr, qg, qb, qa)
    }
  }

  return null
}

/**
 * 判断文本是否为可识别的颜色值。
 * @param {string} content 文本
 * @returns {boolean} 是否为颜色
 */
function isColorText(content) {
  return normalizeColorValue(content) !== null
}

// ============ 文本子类型分类 ============

/**
 * 分类纯文本的子类型：html / url / path / color / code / text。
 * @param {string} content 文本内容
 * @returns {string} 子类型
 */
function classifyText(content) {
  const trimmed = content.trim()
  // HTML（来自 QQ、浏览器等）
  if (/<\s*(img|html|body|div|span|p|meta|table)\b/i.test(trimmed))
    return "html"
  // 单个 URL
  if (/^https?:\/\/\S+$/i.test(trimmed))
    return "url"
  // 多行 URL 列表
  if (trimmed.split("\n").every(l => /^https?:\/\/\S+$/i.test(l.trim()) || l.trim() === "")) {
    if (trimmed.indexOf("http") !== -1)
      return "url"
  }
  // 路径
  if (/^(\/[\w.\-]+)+\/?$/.test(trimmed))
    return "path"
  // 颜色值（来自取色器及常见 CSS / Qt 格式）
  if (isColorText(trimmed))
    return "color"
  // 类代码（含花括号、分号、关键字、比较运算符等）
  let codeScore = 0
  if (trimmed.indexOf("{") !== -1 && trimmed.indexOf("}") !== -1)
    codeScore++
  if (/;\s*$/.test(trimmed) || /;\s*\n/.test(trimmed))
    codeScore++
  if (/\b(function|const|let|var|import|def|class|return|if|for|while)\b/.test(trimmed))
    codeScore++
  if (/[=!<>]{2,}/.test(trimmed))
    codeScore++
  if (codeScore >= 2)
    return "code"
  return "text"
}

// ============ HTML 解析 ============

/**
 * 从 HTML 中提取所有 <img src>（本地路径 / 远程 URL / data URI）。
 * @param {string} html HTML 文本
 * @returns {string[]} 图片来源数组
 */
function extractHtmlImageSrcs(html) {
  const srcs = []
  const re = /<img[^>]+src\s*=\s*["']([^"']+)["']/gi
  let match
  while ((match = re.exec(html)) !== null) {
    const src = match[1]
    if (src.startsWith("file://")) {
      srcs.push(src)
    } else if (src.startsWith("/")) {
      srcs.push(src)
    } else if (src.startsWith("data:image/")) {
      srcs.push(src) // base64 data URI
    } else if (/^https?:\/\//i.test(src)) {
      srcs.push(src) // 远程 URL
    }
  }
  return srcs
}

/**
 * 解码 HTML 实体（命名实体与十进制 / 十六进制数字实体）。
 * @param {string} text 含实体的文本
 * @returns {string} 解码后的文本
 */
function decodeHtmlEntities(text) {
  let s = String(text === undefined || text === null ? "" : text)
  s = s.replace(/&nbsp;/gi, " ").replace(/&lt;/gi, "<").replace(/&gt;/gi, ">").replace(/&amp;/gi, "&").replace(/&quot;/gi, "\"").replace(/&apos;/gi, "'").replace(/&#39;/g, "'")

  s = s.replace(/&#x([0-9a-fA-F]+);/g, (_, hex) => {
    const code = parseInt(hex, 16)
    if (!isFinite(code) || code <= 0)
      return ""
    if (String.fromCodePoint)
      return String.fromCodePoint(code)
    return code <= 0xFFFF ? String.fromCharCode(code) : CHAR_REPLACEMENT
  })
  s = s.replace(/&#([0-9]+);/g, (_, dec) => {
    const code = parseInt(dec, 10)
    if (!isFinite(code) || code <= 0)
      return ""
    if (String.fromCodePoint)
      return String.fromCodePoint(code)
    return code <= 0xFFFF ? String.fromCharCode(code) : CHAR_REPLACEMENT
  })
  return s
}

/**
 * 把 HTML 转为纯文本（去脚本/样式、块级标签转换行、解码实体、压缩空白）。
 * @param {string} html HTML 文本
 * @returns {string} 纯文本
 */
function htmlToPlainText(html) {
  let s = sanitizeClipboardText(html)
  s = s.replace(/<\s*(script|style)\b[^>]*>[\s\S]*?<\s*\/\s*\1\s*>/gi, " ")
  s = s.replace(/<\s*br\s*\/?>/gi, "\n")
  s = s.replace(/<\s*\/\s*(p|div|li|tr|h[1-6])\s*>/gi, "\n")
  s = s.replace(/<\s*(p|div|li|tr|h[1-6])\b[^>]*>/gi, "\n")
  s = s.replace(/<[^>]*>/g, "")
  s = decodeHtmlEntities(s)
  s = s.split(CHAR_NBSP).join(" ")
  s = s.replace(/[ \t]+\n/g, "\n").replace(/\n[ \t]+/g, "\n")
  s = s.replace(/[ \t]{2,}/g, " ")
  s = s.replace(/\n{3,}/g, "\n\n")
  return s.trim()
}

/**
 * 判断一段 HTML 是否应当当作纯文本处理（只含简单内联样式标签、无图片/链接/表格等）。
 * @param {string} html HTML 文本
 * @param {string} [plainText] 已转好的纯文本（不传则内部转换）
 * @returns {boolean} 是否更适合按纯文本展示
 */
function shouldTreatHtmlAsPlainText(html, plainText) {
  const s = sanitizeClipboardText(html).trim()
  if (!s)
    return false
  if (!/<\s*[a-z!/]/i.test(s))
    return false
  if (/<\s*(img|svg|video|audio|canvas|iframe|object|embed|table|ul|ol|pre|code|blockquote)\b/i.test(s))
    return false
  if (/<\s*a\b[^>]*\bhref\s*=/i.test(s))
    return false

  const allowed = {
    "html": true, "body": true, "span": true, "font": true,
    "b": true, "strong": true, "i": true, "em": true, "u": true,
    "s": true, "strike": true, "sub": true, "sup": true,
    "br": true, "p": true, "div": true
  }
  const tagRe = /<\s*\/?\s*([a-zA-Z0-9:-]+)/g
  let m
  while ((m = tagRe.exec(s)) !== null) {
    const tag = String(m[1] || "").toLowerCase()
    if (!tag || tag.charAt(0) === "!")
      continue
    if (!allowed[tag])
      return false
  }

  const plain = String(plainText === undefined || plainText === null ? htmlToPlainText(s) : plainText).trim()
  if (!plain)
    return false
  const visible = decodeHtmlEntities(s.replace(/<[^>]*>/g, "")).replace(/\s+/g, "")
  if (!visible)
    return false
  return true
}

// ============ 本地路径 / URL ============

/**
 * 把本地路径转成 file:// URL（仅接受绝对路径）。
 * @param {string} path 路径
 * @returns {string} file:// URL；非绝对路径返回空串
 */
function localFileUrl(path) {
  const normalized = normalizeLocalPath(path)
  if (!normalized || normalized.charAt(0) !== "/")
    return ""
  return "file://" + normalized
}

// ============ 二进制图片元数据 ============

/**
 * 规范化二进制图片扩展名（jpg→jpeg、tif→tiff、svg+xml→svg）。
 * @param {string} ext 原始扩展名
 * @returns {string} 规范扩展名
 */
function normalizeBinaryExt(ext) {
  const e = (ext || "").toLowerCase()
  if (e === "jpg")
    return "jpeg"
  if (e === "tif")
    return "tiff"
  if (e === "svg+xml")
    return "svg"
  return e
}

/**
 * 从 cliphist 的「[[ binary data … ]]」描述里解析图片扩展名。
 * @param {string} content 描述文本
 * @returns {string} 扩展名，默认 png
 */
function binaryExtFromMeta(content) {
  const m = content.match(/^\[\[\s*binary data\s+.+?\s+([A-Za-z0-9.+\/-]+)\s+[0-9]+x[0-9]+\s*\]\]$/)
  if (!m)
    return "png"
  let raw = m[1]
  const slash = raw.indexOf("/")
  if (slash !== -1)
    raw = raw.substring(slash + 1)
  const e = normalizeBinaryExt(raw)
  return e || "png"
}

/**
 * 从二进制描述里解析图片尺寸。
 * @param {string} content 描述文本
 * @returns {string} 形如 "1920 x 1080"；无则空串
 */
function binaryDimensionsFromMeta(content) {
  const m = content.match(/(\d+)x(\d+)\s*\]\]$/)
  if (m)
    return m[1] + " x " + m[2]
  return ""
}

/**
 * 从二进制描述里解析文件大小。
 * @param {string} content 描述文本
 * @returns {string} 人类可读大小；无则空串
 */
function binarySizeFromMeta(content) {
  const m = content.match(/binary data\s+(\d+)\s/)
  if (m) {
    const bytes = parseInt(m[1])
    if (bytes > 1048576)
      return (bytes / 1048576).toFixed(1) + " MB"
    if (bytes > 1024)
      return (bytes / 1024).toFixed(1) + " KB"
    return bytes + " B"
  }
  return ""
}

/**
 * 识别「[Binary Image: image/xxx]」占位文本并取出其 mime。
 * @param {string} textValue 文本
 * @returns {string} 小写 mime；非占位返回空串
 */
function placeholderImageMime(textValue) {
  const m = String(textValue === undefined || textValue === null ? "" : textValue).trim().match(/^\[Binary Image:\s*(image\/[A-Za-z0-9.+-]+)\]$/i)
  return m ? m[1].toLowerCase() : ""
}

/**
 * 从内容中提取所有 file:// 本地绝对路径（去重、剔除替换符与控制字符）。
 * @param {string} content 内容
 * @returns {string[]} 路径数组
 */
function extractFilePaths(content) {
  const paths = []
  const src = sanitizeClipboardText(content)
  const re = /file:\/\/([^\s]+)/g
  let match
  while ((match = re.exec(src)) !== null) {
    let p
    try {
      p = decodeURIComponent(match[1])
    } catch (e) {
      p = match[1]
    }
    p = String(p || "").split(CHAR_REPLACEMENT).join("").replace(CTRL_CHARS_RE, "")
    if (p.startsWith("localhost/"))
      p = "/" + p.substring("localhost/".length)
    if (!p || p.charAt(0) !== "/")
      continue
    if (paths.indexOf(p) === -1)
      paths.push(p)
  }
  return paths
}
