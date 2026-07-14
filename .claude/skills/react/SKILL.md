---
name: react
description: 编写或修改 React/TSX/JSX 组件、Hooks、自定义 Hook、useState/useEffect、forwardRef、memo、@preact/signals-react/signal 状态，或在用户自己的前端项目中需要复用 hooks/comps/utils 等内部包约定时调用。外部项目需先读项目配置和现有风格，不强行套用内部约定
---

> **必读**：本 Skill 包含项目强制规范。涉及 React 相关任务时，必须先读取全文再写代码，禁止跳过或遗漏

## 适用范围
- 优先适用于当前用户自己的前端项目，尤其是存在 `hooks`、`comps`、`utils`、`@preact/signals-react` 约定的仓库
- 外部项目、开源项目、无这些内部包的项目，先读项目配置和现有代码风格，不强行套用内部包、signal、memo、useLatestCallback 等规则
- 项目已有明确规范时，以项目配置、现有代码和 AGENTS.md / CLAUDE.md 为准

## 项目可用工具
```ts
import {
  // 事件相关
  useOnWinHidden, useBindWinEvent, useClickOutside, useShortCutKey, useDoubleKeyDown, useMouse,
  // 滚动相关
  useScrollBottom, useScrollReachBottom, useScrollRestore, useWheelDirection,
  // 生命周期，effect 可接收 async fn
  useRefresh, onMounted, onUnmounted, useUpdateEffect, useCustomEffect,
  // 网络请求
  useReq, useWatchReq,
  // 观察器
  useIntersectionObserver, useResizeObserver, useMutationObserver,
  // 状态管理
  useThrottleState, useDebounceState, useWatchDebounceState, useWatchThrottleState, useToggleState, useStable, useLatestRef, useGetState, useAutoSave,
  // 防抖节流函数
  useDebounceFn, useThrottleFn,
  // 主题相关
  useTheme, useChangeTheme, useToggleThemeWithTransition,
  // 订时器
  useDefer, useTimer,
  // Ref 相关
  useComposedRef, useConst, useLatestCallback,
  // 元素坐标相关
  useElBounding, useFloatingPosition,
  // DOM 相关
  useInsertStyle, vShow, useRestoreFocus,
  // 其他 Hooks
  useStateWithPromise, useTextOverflow, useViewportHeight, useWorker,
} from 'hooks' // packages/hooks

import {
  // 基础组件
  Button, Card, Icon, Badge, CloseBtn, Arrow, Tooltip, Copy,
  // 输入组件
  Input, Textarea, ChatInput, SearchBar, MdEditor,
  // 选择器组件
  Select, Checkbox, Radio, Switch, Slider, Cascader, DatePicker,
  // 表单组件
  Form, Uploader,
  // 弹窗组件
  Modal, Drawer, Popover, Dropdown, ContextMenu,
  // 反馈组件
  Loading, Notification, EmptyState, ErrorState, Skeleton, Progress, Message, Mask,
  // 轮播组件
  Carousel,
  // 布局组件
  SplitPane, Spacer, Separator, Sidebar, CollapsibleSidebar, Toolbar, NavBar,
  // 数据展示
  Table, Pagination, Tabs, Steps, TextOverflow,
  // 功能组件
  KeepAlive, HtmlPreview, TourGuide,
  // 滚动组件
  InfiniteScroll, VirtualScroll, VirtualDyScroll, VirtualWaterfall, SeamlessScroll, PageSwiper,
  // 图片组件
  ImgThumbnails, LazyImg, PreviewImg, RetryImg, ImgTransition,
  // 动画组件
  Animate, AutoScrollAnimate, FlipItem, TransitionItem, TextFadeIn, TextReveal, HeroEnterText,
  // 背景组件
  BgPaths, BlurBgImg, GridBg, DyBgc, GradientBoundary, GradientText, LiquidGlass,
} from 'comps' // packages/comps

import {
  // 工具函数
  cn, addTimestampParam, extractLinks, normalizeEOL, isValidFileType, composeBase64,
  // React 工具
  getCompKey, filterValidComps, injectReactApp,
  // 样式管理
  svgStyle, createZIndexStore,
  // Markdown
  mdToHTML,
  // 光标坐标
  getCursorCoord, trackCursorCoord,
  // Suspense
  createSuspenseData,
} from 'utils' // packages/utils
```

---

## 组件模板
```tsx
import { cn } from 'utils'
import { memo } from 'react'

export const Demo = memo<DemoProps>((props) => {
  const {
    style,
    className,
  } = props

  return (
    <div
      className={ cn(
        'DemoContainer',
        className
      ) }
      style={ style }
    >

    </div>
  )
})

Demo.displayName = 'Demo'

export type DemoProps = {

}
& React.PropsWithChildren<React.HTMLAttributes<HTMLElement>>

// 类型单独放 types.ts
export type CompRef = { }
export type CompProps = { } & React.PropsWithChildren<React.HTMLAttributes<HTMLElement>>
```

---

## 代码要求
- 组件化：一个组件一个文件，具名导出
- 单一职责：避免在组件内堆复杂 effect / 业务逻辑，优先单独写 `useXxx.ts` 作为逻辑封装
- HTML/JSX 结构：避免无用的 div 包装，保持简洁，同时确保组件根元素能透传所有属性，使用 `React.PropsWithChildren<React.HTMLAttributes<HTMLElement>>` 作为组件 props 基础
- 优化：项目中组件必须 `memo`；回调用 `useLatestCallback` 替代 `useCallback`（见下方说明）
- 路由：`/views/**/page.tsx` 直接 `export default`，它会被自动加入路由
- 目录：`组件名/index.tsx` 或 `index.ts` 统一导出
- 组件库：优先用 `packages/comps` 已有组件

## CSS Style
- TailwindCSS：用根目录设计 Token，无法实现时用行内样式，必须用 CSS 时用 `.module.scss`
- 类名：禁止未定义类名，用 `bg-[#409eff]` 语法，禁止动态拼接 `h-[${h}px]`
- 深色模式：`tailwind.config` 变量已自动适配，无需 `dark:` 前缀

## 库
- 禁止：shadcn/ui
- 推荐：lucide-react（图标）、`cn`(clsx+tailwind-merge)、class-variance-authority、motion/react

## 性能优化
- 列表渲染：只传递单个 item，避免传递整个数组
- props 传递: 尽量传递基本数据类型，避免对象造成大面积更新

---

## Hooks 基本规则
- **调用位置**：Hooks 必须在组件函数的顶层调用，严禁在条件语句、循环、嵌套函数中调用
  ```tsx
  // 错误：条件调用
  if (condition) {
    const [state, setState] = useState(0)
  }

  // 错误：循环中调用
  for (let i = 0; i < 10; i++) {
    useEffect(() => { ... })
  }

  // 错误：嵌套函数中调用
  const handleClick = () => {
    const [state, setState] = useState(0)
  }

  // 错误：条件调用
  if (condition) return null
  const useXx = useCallback(() => { ... }, [])

  // 正确：顶层调用
  const [state, setState] = useState(0)
  const handleClick = () => { ... }
  ```

- **命名规范**：自定义 Hooks 必须以 `use` 开头（如 `useFetch`、`useForm`），这是 React 识别 Hook 的唯一方式
- **调用顺序**：组件每次渲染时，Hooks 必须以相同的顺序调用，这是 React 正确工作的前提
- **依赖数组**：useEffect、useMemo 的依赖数组必须包含所有外部引用的变量；**回调一律用 useLatestCallback，无需把函数放进依赖项**
- **不要在普通函数中调用 Hooks**：Hooks 只能在 React 组件或自定义 Hook 中调用

### useEffect 使用规范

**写 useEffect 前先问：是否在和外部系统同步？** 外部系统 = WebSocket、浏览器 API（IntersectionObserver 等）、第三方库、定时器。如果 effect 里碰的全是 React 管的东西（props/state/派生值），大概率不需要 effect

**派生值不走 effect**，直接计算或 useMemo，effect + setState 会多一次渲染：
```tsx
// ❌ 多一次渲染
useEffect(() => {
  setVisible(list.filter(item => item.active))
}, [list])

// ✅ 渲染阶段直接算
const visible = list.filter(item => item.active)
// 计算量大时用 useMemo
const visible = useMemo(() => list.filter(item => item.active), [list])
```

**事件不绕 effect**，用户操作直接在事件处理器里做：
```tsx
// ❌ 多余的 flag + effect
useEffect(() => { if (submitted) doSearch() }, [submitted])

// ✅ 直接在事件里做
const handleSubmit = () => doSearch()
```

**禁止链式 effect**（级联 setState），改在同一事件处理器里批量更新：
```tsx
// ❌ 三次渲染
useEffect(() => { setCity('') }, [country])
useEffect(() => { setDistrict('') }, [city])

// ✅ 一次渲染
const handleCountryChange = (val: string) => {
  setCountry(val)
  setCity('')
  setDistrict('')
}
```

**合法场景**（必须写 cleanup）：
```tsx
useEffect(function connectChat() {
  const conn = createConnection(roomId)
  conn.connect()
  return function disconnect() { conn.disconnect() }
}, [roomId])
```

> 数据请求用项目已有的 `useReq` / `useWatchReq`，禁止手写 fetch effect

---

### useLatestCallback 替代 useCallback
在适用项目中用 `useLatestCallback` 替代 `useCallback`。不传依赖数组，内部始终持有并调用「当前最新的函数」，无需把函数作为依赖项，解决 React 闭包陈旧（stale closure）问题；返回的包装函数引用稳定，可放心传给子组件、定时器或 effect

```tsx
import { useLatestCallback } from 'hooks'

// ✅ 推荐：无需 deps，永远调最新逻辑
const handleSubmit = useLatestCallback(() => {
  submit(formData)
})

// ❌ 避免：useCallback 易漏写 deps 导致闭包陈旧
const handleSubmit = useCallback(() => {
  submit(formData)
}, [formData]) // 漏写 submit 就踩坑
```

---

## 闭包陷阱
state 在 fn1 被 setState 后立即调用 fn2，fn2 读取 state 拿不到最新值（React 未立即更新）。用项目中的 `useGetState.ts` 解决，没有则告知

```tsx
// 问题：fn2 拿不到最新 count
const [count, setCount] = useState(0)

const fn1 = () => {
  setCount(count + 1)
  fn2() // count 仍是旧值
}
const fn2 = () => {
  console.log(count) // 0
}

const handleXx = () => {
  fn1()
  fn2() // 无法获取最新值
}
```

```tsx
// 解决：useGetState
import { useGetState } from 'hooks'

const [count, setCount] = useGetState(0)
const fn2 = () => {
  console.log(setCount.getLatest()) // 1
}
```

---

## Hooks 封装规范 (稳定性与 Refs)
在封装通用 Hooks 时，需平衡“开发体验”与“性能开销”，遵循以下精准优化原则：

### useStable (引用稳定化)
- **准则**：仅针对可能导致死循环的**复杂对象/数组**使用（如用户经常直接传入的 `options={{...}}`）
- **禁止基础类型**：严禁对 string, number, boolean 等基础类型使用
  - *原因*：React 依赖项对比（Object.is）对基础类型天然高效，封装 `useStable` 会引入多余的 Ref 存储和 `deepCompare` 计算开销

---

## 状态管理 Signal
Signal 可以有效解决 React 闭包陷阱等问题。以下规则仅适用于已采用 `@preact/signals-react` 的项目

1. **通用组件库**（`src/components`、`packages/comps`）：不使用 signal（`@preact/signals-react`），以保证组件库的可移植性与兼容性。可以使用 React 内置 API 以及项目自有的 `hooks`、`utils` 等 workspace 包
2. **其他所有地方**（业务页面、业务组件、状态共享等）：优先使用 `@preact/signals-react`（signal、computed、useSignal 等），避免无必要的 useState/useReducer

| 类型 | 说明 | 参考 |
|------|------|------|
| Signal 与 Hooks | signal、computed、useSignal、useComputed、useSignalEffect、useSignals | [references/signal-and-hooks.md](references/signal-and-hooks.md) |
| Effect 与订阅控制 | effect、batch、peek、untracked | [references/effect-and-tracking.md](references/effect-and-tracking.md) |
| Signal Ref | useSignalRef、useLiveSignal | [references/signal-ref.md](references/signal-ref.md) |
| Show / For | 条件渲染与列表 | [references/show-and-for.md](references/show-and-for.md) |
| 渲染优化 | 直接传 signal vs .value | [references/rendering.md](references/rendering.md) |

Detail in references/; read when implementing specific APIs
