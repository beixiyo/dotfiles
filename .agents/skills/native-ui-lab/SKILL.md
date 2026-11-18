---
name: native-ui-lab
description: 桌面端（Electron / 原生窗口）视觉与窗口行为的实验式排查：把「看起来不对」改写成可重复实验，独立实验进程 + 参数扫描 + 固定取景截图 + 像素取样 + 拼图对比，用测量代替猜测。满足任一即用：视觉结果涉及另一个进程的内容（毛玻璃透出别的 App、贴合别的 App 的窗口）；行为只在特定窗口状态出现（非激活、不可聚焦、全屏之上、别的 Space、系统弹层期间）；用户截图与代码推断矛盾（材质 / 透明度 / 层级 / 深浅色不符）；偶现的系统弹层（密码、Touch ID、sheet）需要抓现场。不用：纯 Web 页面内部布局样式走 playwright-cli；日志、类型、测试能定位的逻辑问题走 debug 或常规排查；只问「支不支持」直接查文档
---

## 核心原则

**不推理渲染结果，去测量它。** 窗口层级、材质外观、焦点归属、跨进程贴合，代码里看到的只是「请求」，操作系统最终画了什么只有截图知道。凡是要回答「为什么看起来是这样」，先把问题改写成能跑多次的实验，再从截图里读答案

一次合格的实验必须同时具备：

| 要素 | 含义 | 缺了会怎样 |
| --- | --- | --- |
| 独立实验进程 | 用项目自带的 Electron 二进制起一个只含被测窗口的最小脚本，不在业务 App 里改代码试 | 每试一个参数重新打包一轮，最后只试了两三个 |
| 参数扫描 | 材质、层级、外观、透明度等由环境变量注入，一次跑完所有候选 | 结论建立在「印象」上 |
| 固定取景截图 | 按被测窗口实际坐标截同一区域，所有样本同一取景 | 肉眼比不出 5% 的差异 |
| 客观量化 | 单点像素、区域均值 / 标准差、拼图并排 | 「好像更透一点」无法与用户对齐 |

## 流程

1. **改写成实验**：写下被测变量、固定条件、判定标准（某像素颜色 / 区域标准差 / 是否出现某窗口）
2. **起独立实验进程**：窗口配置与业务窗口逐项对齐（`type`、`focusable`、`transparent`、材质、层级）。要渲染业务真实产物时 `loadFile` 构建出的 html，用 preload 在主世界注入假 IPC 喂数据；要定位**别的进程**的窗口时写几十行原生 CLI 输出 JSON。骨架见 [references/electron-lab.md](references/electron-lab.md)
3. **固定取景逐参数截图**：先把背景 App 拉到前面，再建实验窗口；截图区域 = 窗口矩形外扩一圈，所有样本共用；改参数 → 等 500 到 700 毫秒 → 截图 → 文件名带参数。偶现的系统弹层用后台循环每秒 dump 窗口列表，让用户在这期间去触发
4. **量化对比**：单点颜色、区域标准差、与用户截图同位置取样、拼图 `open` 给用户看。命令见 [references/capture-recipes.md](references/capture-recipes.md)
5. **下结论交代边界**：结论引用样本（哪张图、哪个像素、哪个数值）；分清平台能力上限与自己代码的问题；做不到的直说，给唯一可行路径及代价

## 平台能力差异

三平台思路相同，但能力不对等，先看这张表再决定实验能做到哪一步：

| 能力 | macOS | Linux | Windows |
| --- | --- | --- | --- |
| 区域截图 | `screencapture -x -R`，终端需「屏幕录制」权限，否则黑图 | X11 `import` / `scrot` 无限制；Wayland 走 `grim`，依赖合成器（wlroots 系可用，GNOME 要 portal） | PowerShell `System.Drawing` 或 `nircmd`，无权限门槛 |
| 读别的进程的窗口矩形 | `CGWindowListCopyWindowInfo`，免权限，能拿 layer 与前后顺序 | X11 `xdotool` / `xwininfo` 可读；Wayland 原则上不允许读其他客户端的窗口几何 | PowerShell 调 `GetWindowRect` / `EnumWindows`，无权限门槛 |
| 原生毛玻璃 | `vibrancy` 系统材质，着色重、最多透一成多，深色下几乎不透；必须配 `visualEffectState: 'active'` 才能在非激活窗口生效 | Electron 无原生方案；靠合成器（KDE 的 blur-behind 属性、GNOME 需扩展），大多数环境做不到 | `backgroundMaterial`（Windows 11 的 mica / acrylic），acrylic 比 macOS 材质透得多；Windows 10 只能 `transparent` |
| 窗口层级 | `setAlwaysOnTop(true, level)` 有 floating / screen-saver 等多级 | 由窗口管理器决定，`level` 参数无效 | 只有 topmost 一级，`level` 参数无效 |
| 不抢焦点的浮窗 | `type: 'panel'` + `focusable: false` + `showInactive`，非激活面板 | `focusable: false` 交给 WM 解释，行为不一 | `focusable: false` 对应 `WS_EX_NOACTIVATE`，可靠 |
| 跨进程拖拽文件 | `webContents.startDrag` 写 NSPasteboard | 同 API，依赖 X11 / Wayland 的 DnD 协议 | 同 API，OLE 拖拽 |
| 自动操作别的 App | `System Events` 需辅助功能权限，没有就只能让用户手动操作 | X11 `xdotool` 可点可键；Wayland 基本不行 | UIAutomation / `SendKeys`，无权限门槛 |
| 读系统外观 | `defaults read -g AppleInterfaceStyle` | `gsettings get org.gnome.desktop.interface color-scheme` | 注册表 `AppsUseLightTheme` |
| 拉起 / 退出别的 App | `open -a`、`osascript -e 'quit app "X"'` | `xdg-open`、`pkill` | `Start-Process`、`Stop-Process` |
| 无头跑 Electron | 不需要 | `xvfb-run` | 不需要 |
| DPI | Retina 截图像素为坐标 2 倍，`-R` 用点坐标；副显示器坐标可为负 | 各显示器缩放可不同 | 缩放因子随显示器，坐标按逻辑像素 |

判断顺序：先看目标平台在表里对应行能不能做，再写实验；一行写着「做不到」的，直接告诉用户是平台上限

## 已踩过的坑

- vibrancy 默认 `visualEffectState: 'followWindow'`，非激活窗口材质被压成实色；不可聚焦、`showInactive` 的窗口必须写 `'active'`
- 深色外观下 macOS 公开材质几乎不透，浅色材质才看得出模糊，这是平台上限
- `screen-saver` 层级高于系统拖拽图像窗口（500），从这种窗口拖出去时图标被自己盖住
- 系统设置的密码确认框是它自己的 layer 0 窗口且排在最前，按「最前面的窗口」定位会贴到确认框上；按面积取主窗口
- `contextBridge` 会序列化对象，Proxy 传不过去；假 IPC 要在 `contextIsolation: false` 下直接赋全局
- zsh 不做单词拆分，`set -- $var` 拿不到多个参数；改数组或让 magick 一次取多点
- `montage -label` 需显式 `-font`，否则报找不到字体
- 后台命令里的 `cd` 不影响后续命令，每条命令自己 `cd`
