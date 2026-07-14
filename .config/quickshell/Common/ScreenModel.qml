// ScreenModel.qml — 屏幕选择工具单例
//
// 根据目标输出名从 Quickshell.screens 中挑选要显示弹窗的屏幕。
// `import qs.Common` 后用 `ScreenModel.targetScreens(...)` 访问。
pragma Singleton

import Quickshell

Singleton {
  /**
   * 选出弹窗应当显示的屏幕列表（供 Variants.model 使用）。
   * @param {var} screens Quickshell.screens 屏幕数组
   * @param {string} targetName 目标输出名（如 "DP-1"）；为空则取首个屏幕
   * @returns {var} 命中的屏幕单元素数组；找不到时回退到首个屏幕
   */
  function targetScreens(screens, targetName) {
    if (!screens || screens.length === 0)
      return []
    if (!targetName)
      return [screens[0]]

    for (let i = 0; i < screens.length; i++) {
      if (screens[i].name === targetName)
        return [screens[i]]
    }
    return [screens[0]]
  }
}
