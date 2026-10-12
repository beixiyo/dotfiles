---
name: react
description: 编写 React 时必须调用
---

## 适用范围
- 涉及特定包、路由或主题机制的条目，先核实当前项目是否提供对应能力，不假定依赖或配置存在
- 项目已有明确规范时，以项目配置、现有代码和 AGENTS.md / CLAUDE.md 为准
- 内部源码模板：本地 `~/Documents/code/frontend/react-tool` or `~/code/frontend/react-tool`，缺失时用 gh 查 https://github.com/beixiyo/react-tool

## 通用项目约定

以下是 React 项目的默认开发约定；依赖特定工具或配置的条目单独注明适用条件

### 代码要求
- 组件化：一个组件一个文件，具名导出
- 单一职责：避免在组件内堆复杂 effect / 业务逻辑，优先单独写 `useXxx.ts` 作为逻辑封装
- HTML/JSX 结构：避免无用的 div 包装，保持简洁，同时确保组件根元素能透传所有属性，使用 `React.PropsWithChildren<React.HTMLAttributes<HTMLElement>>` 作为组件 props 基础
- 优化：项目中组件必须 `memo`；项目提供 `useLatestCallback` 时用它替代 `useCallback`（见下方说明）
- 路由：采用 `/views/**/page.tsx` 自动路由约定的项目，页面直接 `export default`；以当前路由配置为准
- 目录：`组件名/index.tsx` 或 `index.ts` 统一导出
- 组件库：见下方「复用优先」；存在 `packages/comps` 时优先从中查找

### 复用优先（写码前强制检查）

- 实现任何 hook、通用组件、工具函数前，先按下方目录地图定位分类，读当前项目对应包的 `src/<分类>/index.ts` 确认导出；命中并且可用则使用
- 核实顺序：package.json / tsconfig paths / 已有 import 是否提供 `hooks`、`comps`、`utils` 别名 → 提供则读导出直接用
- 组件一组件一文件夹：`ls comps/src/components` 即得全部可用组件，无需记忆清单
- 地图与实际源码不符时以源码为准，并顺手更新本 skill（通知用户）

**hooks（packages/hooks/src，从包名 `hooks` 导入）**

| 分类 | 覆盖需求 | 代表导出 |
|------|----------|----------|
| `dom/` | 元素尺寸、位置、视口、焦点 | `useElBounding` `useAutoResize` `useFloatingPosition` `useViewportHeight` `useMediaQuery` `useTextOverflow` `useRestoreFocus` |
| `event/` | 事件监听、快捷键、滚动行为 | `useClickOutside` `useShortCutKey` `useMouse` `useScrollBottom` `useScrollReachBottom` `useScrollRestore` `useScrollIntoView` `useWheelSwipe` `useBindWinEvent` `useOnWinHidden` `useKeyboardLayer` |
| `state/` | 状态、防抖节流 | `useGetState` `useAutoSave` `useStateWithPromise` `useToggleState` `useDebounceState` `useThrottleState` `useWatchDebounceState` `useWatchThrottleState` `useDebounceFn` `useThrottleFn` `vShow` |
| `theme/` | 主题 | `useTheme` `useChangeTheme` `useToggleThemeWithTransition` |
| `lifecycle.ts` | 生命周期与 effect | `onMounted` `onUnmounted` `useCustomEffect`（可接 async）`useUpdateEffect` `useRefresh` |
| `net.ts` | 请求与网络状态 | `useReq` `useWatchReq` `useOnlineStatus` |
| `ob.ts` | 观察器 | `useIntersectionObserver` `useResizeObserver` `useMutationObserver` |
| `memo.ts` | 稳定引用 | `useLatestCallback` `useStable` `useConst` |
| `ref.ts` | ref 增强 | `useLatestRef` `useComposedRef` |
| `timer.ts` | 定时与延迟帧 | `useTimer` `useDefer` |
| 根文件 | 其他 | `useWorker` `useNotifyParentReady` |

**comps（packages/comps/src/components）**：一组件一文件夹，`ls` 即得全部；另有 `hooks/`、`utils/`、`icons/`、`i18n/` 子目录

**utils（packages/utils/src，文件名即分类）**：`tool.ts`（`cn` 等）、`reactTool.ts`（`getCompKey` `filterValidComps` `injectReactApp`）、`md.ts` 与 `markdown/`（`mdToHTML`）、`getCursorCoord.ts`、`createSuspenseData.ts`、`styleManager.ts`（`svgStyle` `createZIndexStore`）、`keyboard/`、`handleMask.ts`

### CSS Style
- TailwindCSS：用根目录设计 Token，无法实现时用行内样式，必须用 CSS 时用 `.module.scss`
- 类名：禁止未定义类名，用 `bg-[#409eff]` 语法，禁止动态拼接 `h-[${h}px]`
- 深色模式：项目主题变量已自动适配时，无需 `dark:` 前缀；以当前主题配置为准

### 库
- 禁止：shadcn/ui
- 推荐：lucide-react（图标）、`cn`(clsx+tailwind-merge)、class-variance-authority、motion/react

### 性能优化
- 列表渲染：只传递单个 item，避免传递整个数组
- props 传递: 尽量传递基本数据类型，避免对象造成大面积更新

---

## Hooks 与状态

- 遵循 Hooks 的调用和依赖规则；派生值在渲染阶段计算，用户事件在处理器内完成，避免用 effect 串联状态更新
- effect 用于外部系统同步；创建订阅、连接或定时器等资源时负责清理

### 内部项目特有 hook 用法

- `useLatestCallback` 替代 `useCallback`；需要重新同步的响应式输入仍应显式表达，具体行为以项目源码为准
- 数据请求沿用项目已有的数据层；有 `useReq` / `useWatchReq` / `tanstack-query` 的项目不手写 fetch effect
- 需要 setState 后同步读取最新值时检查项目 `useGetState` 的能力
- 组件接收对象/数组 props 时，在组件入口用 `useStable` 按内容稳定引用；例如 `const images = useStable(incomingImages)`
- `useStable` 是深比较：非普通数据对象（DOM、React 元素、类实例等），或数据量大到深比较得不偿失时不要用
- 需要同步 ref 为最新值的场景，使用 `useLatestRef`
- 网络检测用 `useOnlineStatus`

## 按需资料

- 新建内部项目组件时参考 [组件模板](references/component-template.md)，局部修改不必加载模板

## 状态管理 Signal
Signal 可以有效解决 React 闭包陷阱等问题。以下规则仅适用于已采用 `@preact/signals-react` 的项目

1. **通用组件库** `packages/comps` 不使用 signal（`@preact/signals-react`），以保证组件库的可移植性与兼容性
2. **其他地方**（业务页面、业务组件、状态共享等）：优先使用 `@preact/signals-react`（signal、computed、useSignal 等），避免无必要的 useState/useReducer

| 类型 | 说明 | 参考 |
|------|------|------|
| Signal 与 Hooks | signal、computed、useSignal、useComputed、useSignalEffect、useSignals | [references/signal-and-hooks.md](references/signal-and-hooks.md) |
| Effect 与订阅控制 | effect、batch、peek、untracked | [references/effect-and-tracking.md](references/effect-and-tracking.md) |
| Signal Ref | useSignalRef、useLiveSignal | [references/signal-ref.md](references/signal-ref.md) |
| Show / For | 条件渲染与列表 | [references/show-and-for.md](references/show-and-for.md) |
| 渲染优化 | 直接传 signal vs .value | [references/rendering.md](references/rendering.md) |

