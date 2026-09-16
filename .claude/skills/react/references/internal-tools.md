# 内部工具目录

以下是内部包的查找线索，不代表所有项目都提供这些导出；使用前核对当前源码和配置

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
