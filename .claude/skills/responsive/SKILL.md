---
name: responsive
description: 当编写响应式布局、涉及多端适配、断点设计、或提到"响应式"/"responsive"/"移动端适配"/"mobile"等关键词时使用。强制 mobile-first 方向，先写移动端样式，再用 min-width 断点渐进增强到桌面端
---

## 核心原则：Mobile-First

**先写移动端样式，再用断点前缀（`min-width`）逐步增强到大屏。**

这是 TailwindCSS 官方、Google Web Fundamentals、MDN 共同推荐的方法论。原因：

- 移动端样式更简单，作为基础更易维护
- 渐进增强（加样式）比优雅降级（减样式）逻辑更清晰
- 移动设备加载更少 CSS，性能更好
- TailwindCSS 原生就是 mobile-first 设计（无前缀 = 所有尺寸，`md:` = `min-width: 768px` 及以上）
- Google 自 2021 年起完全采用 mobile-first indexing，移动端体验直接影响 SEO

> **例外**：后台管理系统、数据面板等**桌面端为主**的产品，用户几乎不会在手机上使用，此时 desktop-first 更实际。判断依据是产品的实际用户设备分布，而非通用最佳实践。

## 编写顺序

1. 先写无前缀样式 → 这就是移动端的样子
2. 加 sm: 前缀   → 640px+ 的调整
3. 加 md: 前缀   → 768px+ 的调整
4. 加 lg: 前缀   → 1024px+ 的调整
5. 加 xl:/2xl:   → 更大屏幕的调整

示例——一个卡片网格：

```html
<!-- 移动端: 单列 → sm: 双列 → lg: 三列 → xl: 四列 -->
<div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4">
  ...
</div>
```

**错误做法（desktop-first）：**

```html
<!-- 反模式：先写桌面端再用 max-width 缩减 -->
<div class="grid grid-cols-4 max-lg:grid-cols-3 max-sm:grid-cols-1">
```

## TailwindCSS 断点速查

| 前缀 | min-width | 典型设备 |
|------|-----------|---------|
| (无) | 0px | 手机（**基础样式**） |
| `sm` | 640px | 大手机 / 小平板 |
| `md` | 768px | 平板 |
| `lg` | 1024px | 笔记本 |
| `xl` | 1280px | 桌面显示器 |
| `2xl` | 1536px | 大屏 |

## 常见适配模式

### 布局结构变化

```html
<!-- 移动端纵向堆叠 → 桌面端横向排列 -->
<div class="flex flex-col lg:flex-row">
  <aside class="w-full lg:w-64 shrink-0">...</aside>
  <main class="flex-1 min-w-0">...</main>
</div>
```

### 显示 / 隐藏

```html
<!-- 移动端汉堡菜单，桌面端侧边栏 -->
<nav class="hidden lg:block">桌面导航</nav>
<button class="lg:hidden">菜单图标</button>
```

### 间距与字号

```html
<!-- 移动端紧凑 → 桌面端宽松 -->
<section class="px-4 py-6 md:px-8 md:py-10 lg:px-16">
  <h1 class="text-2xl md:text-3xl lg:text-4xl">...</h1>
</section>
```

## 检查清单

- [ ] 基础样式（无前缀）是否就是移动端期望的效果
- [ ] 断点是否从小到大渐进增强（`sm` → `md` → `lg`）
- [ ] 是否避免了 `max-*` 前缀（除非极少数仅限小屏的样式）
- [ ] 触摸目标是否足够大（移动端最小 44x44px）
- [ ] 横向滚动是否被避免（移动端 `overflow-x-hidden`）
