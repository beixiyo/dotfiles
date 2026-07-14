---
name: layout
description: 当编写前端页面布局、涉及高度传递、容器尺寸、flex/grid 布局结构时使用。确保父容器正确传递高度（h-full），定高区域用语义化常量统一管理，主区域用 calc 自适应
---

## 核心问题

CSS 高度不会像宽度那样自动撑满父容器。如果父容器没有显式高度，子组件的 `height: 100%` / `h-full` 无效，导致布局塌陷

## 规则

### 1. 高度链必须完整

从根节点到目标容器的**每一层**都必须有明确高度，链条中断则子组件无法获取高度：

```
html (h-full) → body (h-full) → #app (h-full) → Layout (h-full) → Content (h-full)
```

在 TailwindCSS 中，确保每一层容器都带 `h-full`（即 `height: 100%`）

### 2. 定高区域用语义化常量管理

页面中通常有多个固定高度区域（顶栏、底栏、面包屑等），将这些值抽为语义化常量统一管理，避免散落在各处的魔法数字：

```typescript
// 按页面区域语义化组织
const LAYOUT = {
  header: { height: 64 },
  breadcrumb: { height: 40 },
  footer: { height: 48 },
  sidebar: { width: 240, collapsedWidth: 64 },
} as const

// 主区域高度 = 总高度 - 所有定高区域
// h-[calc(100%-104px)]  即 100% - header(64) - breadcrumb(40)
```

**原则：**
- 常量名反映**语义**（`header.height`），而非 `TOP_BAR_64`
- 用 `as const` 保证类型字面量
- 同一个定高值只在常量对象中定义一次
- 计算时引用常量，注释说明计算过程

### 3. 主区域用 calc 自适应

定高区域占固定空间，**剩余区域**用 `calc(100% - 固定高度之和)` 自动填充：

```html
<div class="h-full flex flex-col">
  <!-- 定高 -->
  <header class="h-16 shrink-0">...</header>
  <!-- 自适应：撑满剩余空间 -->
  <main class="h-[calc(100%-64px)] overflow-auto">...</main>
</div>
```

或用 flex 的 `flex-1` + `min-h-0` 替代 calc（flex 场景下更简洁）：

```html
<div class="h-full flex flex-col">
  <header class="h-16 shrink-0">...</header>
  <main class="flex-1 min-h-0 overflow-auto">...</main>
</div>
```

> `min-h-0` 是关键——flex 子项默认 `min-height: auto`，会阻止内容收缩，导致溢出而非滚动

### 4. 检查清单

编写布局时逐项确认：
- [ ] 高度链从根到目标容器是否完整（每层 `h-full`）
- [ ] 定高区域是否抽为常量，而非硬编码
- [ ] 主区域是否用 `calc` 或 `flex-1 min-h-0` 自适应
- [ ] 可滚动区域是否加了 `overflow-auto`
- [ ] 定高区域是否加了 `shrink-0` 防止被压缩
