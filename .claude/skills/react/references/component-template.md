# 内部组件模板

用于已采用 hooks/comps/utils 约定的项目，按当前组件职责和类型约定调整

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
