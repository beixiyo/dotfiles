# 内部组件模板

用于已采用 hooks/comps/utils 约定的项目，按当前组件职责和类型约定调整

## 组件模板
```tsx
import { cn } from 'utils'
import { memo, type ComponentPropsWithoutRef } from 'react'

export const Demo = memo<DemoProps>((props) => {
  const {
    style,
    className,
    children,
    ...restProps
  } = props

  return (
    <div
      { ...restProps }
      className={ cn(className) }
      style={ style }
    >
      { children }
    </div>
  )
})

Demo.displayName = 'Demo'

/** Demo 根元素支持的属性，包含 children；不声明尚未实现的 ref 接口 */
export type DemoProps = ComponentPropsWithoutRef<'div'>
```

新增业务 props 时先解构消费，避免透传到 DOM；通过 `cn` 合并组件样式与外部 `className`，组件自身的样式类放在 `className` 之前。独立类型文件按项目约定组织
