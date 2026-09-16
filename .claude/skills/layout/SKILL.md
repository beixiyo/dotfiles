---
name: layout
description: 设计或排查前端容器尺寸、剩余空间分配与滚动边界；适用于高度传递和 flex/grid 布局
---

## 尺寸来源与滚动边界

先确认容器尺寸来自视口、父容器、内容还是 flex/grid 分配，再沿实际约束定位问题。目标是让内容按预期填充、收缩和滚动

- 使用 `height: 100%` / `h-full` 时，检查包含块是否提供可解析的高度；仅在依赖百分比高度的链条上补齐约束
- 分配剩余空间时沿用项目现有的 flex/grid 结构。需要内容收缩时检查 `min-h-0` / `min-w-0`，grid 轨道必要时使用 `minmax(0, 1fr)`
- 明确由哪个容器滚动，在该容器设置合适的 overflow；检查内容过长时是否出现意外页面滚动、裁切或嵌套滚动
- 需要保持尺寸的 flex 区域使用 `shrink-0`；内容自适应的区域不强行定高

## 从根节点传递高度

对于依赖 `h-full` 填满视口的应用布局，从根节点到目标容器通常需要完整传递高度。排查高度塌陷或滚动异常时，沿祖先链检查，不能只给末端组件加 `h-full`：

```text
html (h-full) → body (h-full) → #app (h-full) → Layout (h-full) → Content (h-full)
```

这条链表示各层都依赖父容器的高度。中间层如果没有提供可解析的高度，下游的百分比高度就可能无法按预期填满。若某层已通过视口高度、固定高度或 flex/grid 分配获得确定尺寸，则从该尺寸来源继续检查，无需机械地给每层添加 `h-full`

## 按页面区域组织固定尺寸

复用项目设计 token、CSS 变量或语义化常量。同一个需要共享或参与计算的尺寸只维护一份，避免样式与计算各自硬编码

页面有多个固定尺寸区域时，按职责组织尺寸，便于样式和计算共同引用：

```typescript
// 按页面区域语义化组织
const LAYOUT = {
  header: { height: 64 },
  breadcrumb: { height: 40 },
  footer: { height: 48 },
  sidebar: { width: 240, collapsedWidth: 64 },
} as const
```

- 名称反映区域职责，例如 `header.height`，而非 `TOP_BAR_64`
- 用 `as const` 保留字面量类型；数值按实际设计调整，已有 token 时复用 token
- 样式与尺寸计算引用同一份值，涉及多个区域的计算用注释说明关系

确实需要显式减去已知尺寸时使用 `calc`；能由布局系统分配的剩余空间直接使用 flex/grid，避免重复计算顶栏等区域高度

## 示例：定高顶栏与可滚动主区域

以下示例假定外层容器的百分比高度可解析：

```html
<div class="h-full flex flex-col">
  <header class="h-16 shrink-0">...</header>
  <main class="flex-1 min-h-0 overflow-auto">...</main>
</div>
```

验证时检查实际尺寸、长内容和预期滚动容器；不以是否包含某个 class 作为布局正确的依据
