## 工作方式

- 先读适用的 `AGENTS.md`、`CLAUDE.md`；*.md 根据模块按需读取，已读且未变化的内容无需重复读取
- 以项目实际依赖、配置和源码为准；不确定的 API 或配置语义先查证。符号、引用和类型查询优先用可用的 LSP，文本和配置用文件搜索
- 只修改任务所需范围。公共 API 变更检查调用方，尽量保持兼容；底层提供通用机制，业务策略由调用方传入
- 区分已修改、已验证与尚未验证；不以静态检查代替运行行为验证
- 编辑后 `~/.claude/hooks/post-write-code.ts` 可能自动格式化，后续以 hook 完成后的磁盘内容为准

## 项目与工具链

项目已有配置优先；没有约束时使用以下偏好：

- 包管理器根据 lock 文件和项目声明判断；优先 pnpm 或 Bun
- 工具链管理优先级：mise > 语言自带管理器 > Homebrew / pacman 等
- 新建前端项目默认 TS + Vite；运行独立 TS 文件使用 `bun run /path/xx.ts`
- monorepo 检查实际使用的 workspace 配置及相关 package 的局部配置；pnpm 项目检查 `pnpm-workspace.yaml`

`@jl-org/*` 均为本人编写，理解行为或排查 bug 时优先读源码和 README。源码通常位于：

- `~/Documents/code/frontend/<repo>`
- `~/code/frontend/<repo>`
- `@jl-org/tool` 本地找不到时用 `gh` 查询 `https://github.com/beixiyo/jl-tool`

## API 与组件

- 多个可选参数或预计扩展的公共函数优先用 options 对象；单一、稳定的必要参数可直接传值
- 新增 options 字段尽量可选；默认值在 API 边界统一归一化，并在公共 JSDoc 中用 `@default` 记录
- 优先声明式 options；运行时策略通过有类型的回调及显式 context 注入。需要命令式 API 时复用同一核心机制
- 资源生命周期由明确的所有者管理，提供对应的清理入口；可能重复调用的清理操作应幂等，异步结果避免向过期状态回写
- 导出的类型和公共函数提供 JSDoc，不重复 TS 类型信息；优先具名导出
- 展示型组件通过 props、slots、children 或回调接收数据与行为；业务编排、路由和全局状态放在容器、Hook 或上层模块
- 组件提供 `className` / `style` 或框架对应的样式覆盖入口。沿用项目样式和动画方案；无约束时优先 TailwindCSS、motion/react 或 motion-v
- UI 偏好简洁冷静，参考 Vercel、Grok、Lovable

## 代码与交流

- 中文回答，除非用户要求其他语言；检索优先英文
- JS/TS 无分号、两格缩进、单引号
- 避免硬编码、隐式全局状态和不必要的抽象层
- TS 类型定义优先放文件底部；代码按逻辑分组留空行，保持呼吸感
- 同类模块用文件夹组织 `index.ts` / `init.lua` 提供统一入口
- 注释和测试描述用中文；对外日志、错误信息默认英文
- 文件职责或复杂边界不明显时补充说明
- 获取网页优先用已有内容、MCP 或 WebFetch；需要转成 Markdown 时可用：

```bash
curl "https://r.jina.ai/https://www.example.com" \
  -H "Authorization: Bearer $JINA_KEY"
```

## Git

- 未经明确要求，不执行修改工作区、暂存区或历史的 Git 命令；只读查询可直接执行
- 用户要求提交时，默认只处理已暂存内容，不擅自 `git add`；用户明确指定暂存范围时按其要求执行

## 验证

- 适合测试的代码改动使用可用的 `how-to-test` skill；纯文档、注释或无有效测试信号的简单改动除外
- 行为测试调用生产代码；不复制实现、扫描源码文本或根据当前实现反推期望值。已有测试覆盖同一失败时不重复添加
- 不为简单 getter、常量、一行 wrapper 或直接算术单独补测试，除非对应真实回归或重要契约；不为覆盖率逐项补分支断言
- Bug 回归测试尽可能证明修复前失败、修复后通过；无法做到时说明验证限制
