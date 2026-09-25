---
name: react
description: 编写或修改 React/TSX/JSX 组件、Hook、useState/useEffect、memo、@preact/signals-react/signal 状态，或在用户自己的前端项目中需要复用 hooks/comps/utils 等内部包约定时调用。外部项目需先读项目配置和现有风格，不强行套用内部约定
---

## 适用范围
- 适用于 React 组件与 Hooks 开发，下方通用约定不以项目是否使用内部包为前提
- 涉及特定包、路由或主题机制的条目，先核实当前项目是否提供对应能力，不假定依赖或配置存在
- 项目已有明确规范时，以项目配置、现有代码和 AGENTS.md / CLAUDE.md 为准
- 内部源码模板在 https://github.com/beixiyo/react-tool

## 通用项目约定

以下是 React 项目的默认开发约定；依赖特定工具或配置的条目单独注明适用条件

### 代码要求
- 组件化：一个组件一个文件，具名导出
- 单一职责：避免在组件内堆复杂 effect / 业务逻辑，优先单独写 `useXxx.ts` 作为逻辑封装
- HTML/JSX 结构：避免无用的 div 包装，保持简洁，同时确保组件根元素能透传所有属性，使用 `React.PropsWithChildren<React.HTMLAttributes<HTMLElement>>` 作为组件 props 基础
- 优化：项目中组件必须 `memo`；项目提供 `useLatestCallback` 时用它替代 `useCallback`（见下方说明）
- 路由：采用 `/views/**/page.tsx` 自动路由约定的项目，页面直接 `export default`；以当前路由配置为准
- 目录：`组件名/index.tsx` 或 `index.ts` 统一导出
- 组件库：优先复用项目已有组件；存在 `packages/comps` 时从中查找

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
- 在采用内部 hooks 包的项目中，回调沿用 `useLatestCallback` 约定；需要重新同步的响应式输入仍应显式表达，具体行为以项目源码为准
- 数据请求沿用项目已有的数据层；采用 `useReq` / `useWatchReq` 的项目不手写 fetch effect
- 需要 setState 后同步读取最新值时检查项目 `useGetState` 的能力
- 内部项目的组件接收对象/数组 props 时，在组件入口用 `useStable` 按内容稳定引用；例如 `const images = useStable(incomingImages)`
- `useStable` 是深比较：非普通数据对象（DOM、React 元素、类实例等），或数据量大到深比较得不偿失时不要用

## 按需资料

- 寻找内部 hooks/comps/utils 的复用入口时读 [内部工具目录](references/internal-tools.md)，再核实当前项目导出与源码
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

Detail in references/; read when implementing specific APIs
