// Fuzzy.qml — 模糊匹配工具单例
//
// 一个轻量的子序列模糊匹配算法：在保持字符顺序的前提下打分，连续匹配、
// 词首匹配、短目标都会加分。`import qs.Common` 后用 `Fuzzy.match(...)` 访问。
pragma Singleton

import Quickshell

Singleton {
  id: root

  /**
   * 对已小写化的 pattern / str 做模糊匹配打分（性能敏感路径直接用本函数避免重复 toLowerCase）。
   * @param {string} pattern 已小写的查询串
   * @param {string} str 已小写的目标串
   * @returns {{ match: boolean, score: number }} 是否命中及得分
   */
  function matchLower(pattern, str) {
    if (!pattern)
      return { match: true, score: 0 }

    let pIdx = 0
    let sIdx = 0
    let score = 0
    let consecutive = 0
    let lastIdx = -1

    while (pIdx < pattern.length && sIdx < str.length) {
      if (pattern[pIdx] === str[sIdx]) {
        if (lastIdx === sIdx - 1) {
          consecutive++
          score += consecutive * 2
        } else {
          consecutive = 0
        }
        if (sIdx === 0 || " -_".includes(str[sIdx - 1]))
          score += 10
        lastIdx = sIdx
        pIdx++
      }
      sIdx++
    }

    if (pIdx === pattern.length) {
      score += Math.max(0, 50 - str.length)
      return { match: true, score: score }
    }
    return { match: false, score: 0 }
  }

  /**
   * 大小写不敏感的模糊匹配（内部会先做 toLowerCase）。
   * @param {string} pattern 查询串
   * @param {string} str 目标串
   * @returns {{ match: boolean, score: number }} 是否命中及得分
   */
  function match(pattern, str) {
    const p = String(pattern === undefined || pattern === null ? "" : pattern).toLowerCase()
    const s = String(str === undefined || str === null ? "" : str).toLowerCase()
    return matchLower(p, s)
  }
}
