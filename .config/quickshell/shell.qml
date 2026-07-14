// shell.qml — Quickshell 统一入口（单一 config root）
//
// 这里是整个 ~/.config/quickshell 配置的唯一入口。通过环境变量 QS_COMPONENT
// 决定本次要加载哪个弹窗组件，再用 Loader 按需实例化——只有被选中的组件会被创建，
// 弹窗「按需启动、退出即关」的行为与原先各自独立的 shell.qml 完全一致。
//
// 这样做的根本原因：Quickshell 的 config root 固定为 shell.qml 所在目录，且会拦截
// （blackhole）root 之外的 import。只有把所有 app 收进同一个 root，各 app 才能共享
// `import qs.Common` 这套公共库（这正是跨项目复用的前提）。
//
// 新增一个 app 时：在 <name>/ 目录下写一个首字母大写的主组件（如 Foo.qml），
// 在下方加一行 Loader + Component 映射即可。
import QtQuick
import Quickshell

import qs.clipboard

ShellRoot {
  id: root

  // 本次要加载的组件名，由 qs-popup 通过 QS_COMPONENT 注入，缺省为剪贴板
  readonly property string component: Quickshell.env("QS_COMPONENT") || "clipboard"

  // ============ 剪贴板 ============
  Loader {
    active: root.component === "clipboard"
    sourceComponent: clipboardComponent
  }
  Component {
    id: clipboardComponent
    Clipboard {}
  }
}
