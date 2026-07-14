// Format.qml — 无状态格式化工具单例
//
// 通用的字节大小、时长格式化等纯函数，跨组件复用。`import qs.Common` 后用
// `Format.bytes(...)` / `Format.duration(...)` 访问。
pragma Singleton

import Quickshell

Singleton {
  /**
   * 把字节数格式化为人类可读大小（B / KB / MB / GB / TB）。
   * @param {number|string} value 字节数
   * @returns {string} 如 "1.5 MB"；非法或非正数返回空串
   */
  function bytes(value) {
    const n = Number(value)
    if (!isFinite(n) || n <= 0)
      return ""

    const units = ["B", "KB", "MB", "GB", "TB"]
    let size = n
    let idx = 0
    while (size >= 1024 && idx < units.length - 1) {
      size /= 1024
      idx++
    }
    return (idx === 0 ? String(Math.round(size)) : size.toFixed(size >= 10 ? 1 : 2)) + " " + units[idx]
  }

  /**
   * 把秒数格式化为时长字符串。
   * @param {number|string} value 秒数
   * @returns {string} 不足 1 小时为 "m:ss"，否则 "h:mm:ss"；非法或非正数返回空串
   */
  function duration(value) {
    const total = Math.round(Number(value))
    if (!isFinite(total) || total <= 0)
      return ""

    const h = Math.floor(total / 3600)
    const m = Math.floor((total % 3600) / 60)
    const s = total % 60
    const pad = n => n < 10 ? "0" + n : String(n)

    return h > 0 ? (h + ":" + pad(m) + ":" + pad(s)) : (m + ":" + pad(s))
  }
}
