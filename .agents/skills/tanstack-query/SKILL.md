---
name: tanstack-query
description: 编写、修改、审查或解释 TanStack Query 代码时使用，覆盖 useQuery、useMutation、QueryClient、query key、缓存同步、预取、失效、乐观更新、并发 mutation 和 v4/v5 迁移。遇到服务器状态管理、请求缓存、列表与详情同步、mutation 后刷新、staleTime/gcTime、isPending/isFetching、setQueryData/setQueriesData、invalidateQueries 或 useMutationState 时使用
---

项目不是 v5、API 语义不确定或涉及版本差异时，先查当前版本官方文档，不凭印象套用 v5

## 状态边界

使用 TanStack Query 管理来自服务器、可能过期且需要同步的数据

不要把以下内容默认放入 Query Cache：

- 表单输入
- 弹窗开关
- 当前 tab
- 尚未提交的纯本地草稿
- 只属于单个组件的派生 UI 状态

Mutation 不会自动同步 Query Cache。调用方必须根据服务端响应决定写缓存还是失效查询

## Query key

顶层使用数组，并包含所有会改变 `queryFn` 结果的输入：

```tsx
export const userKeys = {
  all: ['users'] as const,
  lists: () => [...userKeys.all, 'list'] as const,
  list: (filters: UserFilters) => [...userKeys.lists(), filters] as const,
  details: () => [...userKeys.all, 'detail'] as const,
  detail: (id: string) => [...userKeys.details(), id] as const,
}
```

遵循：

- 从资源到范围再到参数：`resource → list/detail → filters/id`
- 共享资源根前缀，支持精确和批量操作
- 把分页、筛选、排序、租户、语言等查询输入放进 key
- 对象属性顺序不影响哈希，数组元素顺序影响哈希
- 不用互不相关的 `cards-todo`、`card-detail` 顶层 key 表示同一资源
- 优先复用 factory，不在调用点散落字符串数组

Query key 描述缓存身份，不会自动建立查询执行依赖

## useQuery

让 `queryFn` 抛出错误并消费 `AbortSignal`（仅在需要的情况下）

```tsx
const userQuery = useQuery({
  queryKey: userKeys.detail(userId),
  queryFn: ({ signal }) => api.user.get(userId, { signal }),
  enabled: userId !== undefined,
})
```

v5 状态语义：

| 状态             | 含义                                 |
| ---------------- | ------------------------------------ |
| `isPending`      | 尚无成功数据                         |
| `isFetching`     | 当前正在请求，包括首次请求和 refetch |
| `isLoading`      | `isPending && isFetching`            |
| `isRefetching`   | 已有数据时正在重新请求               |
| `isLoadingError` | 首次加载失败，没有可展示数据         |
| `isRefetchError` | 已有数据时后台请求失败               |

注意：

- v5 `useQuery` 没有 `isIdle` 和 `remove`
- v5 Query options 没有 `onSuccess`、`onError`、`onSettled`
- stale 缓存仍可立即展示，随后可能后台 refetch
- query key 变化不会无条件终止旧请求；底层请求必须消费 `signal`
- `select` 只转换 observer 暴露的数据，不覆盖 Query Cache

浏览器端默认 `staleTime: 0`，inactive query 默认 `gcTime: 5 分钟`

## QueryClient 方法选择

| 目标                               | 方法                |
| ---------------------------------- | ------------------- |
| 读取一个精确 key                   | `getQueryData`      |
| 更新一个精确 key                   | `setQueryData`      |
| 按 filter 更新多个已有 Query       | `setQueriesData`    |
| 标记 stale，并按策略 refetch       | `invalidateQueries` |
| 立即重新请求                       | `refetchQueries`    |
| 提前请求并填充缓存                 | `prefetchQuery`     |
| 返回已有数据或请求数据             | `ensureQueryData`   |
| 取消进行中的请求                   | `cancelQueries`     |
| 删除匹配 Query                     | `removeQueries`     |
| 清空 Query Cache 和 Mutation Cache | `clear`             |

`setQueryData` 与 `setQueriesData` 的单复数指 Query 数量，不是缓存值是对象还是数组

`setQueriesData`：

- 使用 query filter 或 key 前缀匹配零到多个现有 Query
- 对每个匹配 Query 分别调用 updater
- 不创建新的 Query

所有 cache updater 必须不可变更新，禁止直接修改 `old`

## invalidateQueries

把行为拆成两步理解：

1. 所有匹配 Query 固定标记为 stale
2. `refetchType` 决定哪些匹配 Query 立即请求

| `refetchType` | 立即请求                             |
| ------------- | ------------------------------------ |
| `'active'`    | 只请求有 observer 的 Query，默认值   |
| `'inactive'`  | 只请求无 observer 但仍有缓存的 Query |
| `'all'`       | 请求 active 和 inactive Query        |
| `'none'`      | 都不请求，只标记 stale               |

## prefetchQuery

`prefetchQuery` 不预测用户行为。调用方在悬停链接、即将跳转或接近下一页时主动调用

预取和正式查询复用同一个 options factory，保证 query key 和 queryFn 一致：

```tsx
export function userDetailOptions(id: string) {
  return queryOptions({
    queryKey: userKeys.detail(id),
    queryFn: ({ signal }) => api.user.get(id, { signal }),
    staleTime: 60_000,
  })
}

void queryClient.prefetchQuery(userDetailOptions(id))

const userQuery = useQuery(userDetailOptions(id))
```

`prefetchQuery` 返回 `Promise<void>`，结果进入 Query Cache；后续相同 key 的 `useQuery` 读取该缓存

## Mutation 后同步缓存

按以下顺序选择：

1. 服务端返回完整可信实体：用 `setQueryData` 更新详情
2. 列表受分页、排序、筛选、权限或服务端派生字段影响：失效列表
3. 响应不完整：失效相关 Query
4. 只需当前 UI 立即反馈：使用 mutation `variables`
5. 多个组件必须共享临时状态：才做 Cache 级乐观更新

不要为了少一次请求在前端复制完整服务端排序和过滤逻辑

请求成功后再 `setQueryData` 是使用 mutation 响应同步缓存，不是乐观更新

## 乐观更新

### 优先 UI 级乐观更新

只影响当前界面时，使用：

- `mutation.isPending`
- `mutation.variables`：调用 `mutate(input)` 时传入的业务数据
- `mutation.submittedAt`：库记录的提交时间，可区分并发 mutation
- `mutation.isError`：失败后保留 variables 并提供重试

跨组件读取时使用 `mutationKey + useMutationState`

`useMutationState` 的 `select` 接收 Mutation Cache 中的库对象：

- `mutation.state` 由 TanStack Query 管理
- `mutation.state.variables` 是业务传给 `mutate` 的数据，由库保存
- `mutation.state.submittedAt` 是库生成的时间戳
- `select` 的返回对象由调用方自己定义

它返回数组，因为一个 `mutationKey` 可能同时存在多个匹配 mutation

### Cache 级乐观更新

仅在多个 Query 消费者必须立即共享临时状态时使用：

1. `cancelQueries`，防止 refetch 覆盖临时数据
2. 保存 snapshot 或可逆 patch
3. `setQueryData` 不可变更新
4. `onError` 回滚本次修改
5. `onSuccess` 用服务端完整结果覆盖临时值
6. `onSettled` 返回 invalidation Promise 做最终校验

```tsx
const updateTodoMutation = useMutation({
  mutationFn: updateTodo,

  onMutate: async (patch) => {
    const queryKey = todoKeys.detail(patch.id)
    await queryClient.cancelQueries({ queryKey })
    const previous = queryClient.getQueryData<Todo>(queryKey)

    queryClient.setQueryData<Todo>(
      queryKey,
      old => old ? { ...old, ...patch } : old,
    )

    return { previous, queryKey }
  },

  onError: (_error, _patch, rollback) => {
    if (rollback?.previous === undefined) return

    queryClient.setQueryData(
      rollback.queryKey,
      rollback.previous,
    )
  },

  onSuccess: (serverTodo) => {
    queryClient.setQueryData(
      todoKeys.detail(serverTodo.id),
      serverTodo,
    )
  },

  onSettled: (_data, _error, patch) =>
    queryClient.invalidateQueries({
      queryKey: todoKeys.detail(patch.id),
    }),
})
```

### 并发边界

完整 snapshot 回滚不天然支持同一实体的并发修改，旧 mutation 失败可能覆盖新 mutation 的成功结果

根据业务明确选择：

- 禁止并发：禁用入口，或为同类 mutation 配置相同 `scope.id`
- UI 级并发：用 `useMutationState` 数组和 `submittedAt` 分别展示
- Cache 级并发：只撤销本次 patch，使用服务端版本号或 request id 防止旧结果回写

不允许同一实体并发写入时，给它们相同的 `scope.id`，TanStack Query 会串行执行：

```tsx
const updateTodoMutation = useMutation({
  mutationFn: updateTodo,
  scope: {
    id: `todo:${todoId}`,
  },
})

updateTodoMutation.mutate({ id: todoId, title: 'A' })
updateTodoMutation.mutate({ id: todoId, title: 'B' })
// B 等 A 完成后再执行
```

TanStack Query 管理 mutation 状态，但不会替业务决定并发写入的冲突语义

## 审查检查表

- 是否确认真实 TanStack Query 版本
- query key 是否包含全部查询输入
- key 是否能按资源前缀批量匹配
- 是否混淆 `isPending`、`isLoading` 和 `isFetching`
- updater 是否原地修改缓存
- mutation 后是否遗漏缓存同步
- 是否把成功后写缓存误称为乐观更新
- invalidation Promise 是否需要 return/await
- 列表更新是否错误复制服务端规则
- 乐观更新是否处理失败和并发
- 本地 optimistic 状态是否被误当成服务端事实
