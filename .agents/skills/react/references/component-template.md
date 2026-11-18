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

/** 包含 children，不声明尚未实现的 ref 接口 */
export type DemoProps =
  & ComponentPropsWithoutRef<'div'>
  & { ... }
```

## 需要暴露 ref 时（React 19）

- 不暴露 ref：`ComponentPropsWithoutRef<'div'>`
- 暴露原生 DOM ref：`ComponentPropsWithRef<'div'>`
- 暴露命令式句柄：`ComponentPropsWithoutRef<'div'> & { ref?: Ref<DemoHandle> }`
- 泛型组件经 `memo` 后会丢失泛型，导出时断言回泛型签名：`memo(InnerX) as <T>(props: XProps<T>) => ReactElement | null`
