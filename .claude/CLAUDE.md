## 项目规范
优先参考项目配置文件（`package.json`、`vite.config.js` 等），mono-repo 注意 `pnpm-workspace.yaml`。这些是理解技术栈的唯一真实来源，不要基于通用知识假设

- 包管理：默认 pnpm or bun，根据项目 lock 文件判断
- 工具链管理优先级：mise > vfox > 语言自带管理器 > Homebrew / pacman 等系统包管理器
- 技术栈：JS 项目默认 TypeScript + Vite（已有其他构建工具则忽略）
- 路径别名：检查 `tsconfig.json` 的 `paths` 配置
- 内部包：`@jl-org/*` 系列均为**本人编写**——理解其行为 / 排查相关 bug 时**优先读源码 README**，勿凭通用知识假设其实现。源码多在本地 `~/Documents/code/frontend/<repo> or ~/code/frontend/<repo>` `@jl-org/tool` 在 https://github.com/beixiyo/jl-tool，如 `gh` cli 可用并且找不到本地源码，可自行查找，或者看 https://github.com/beixiyo 仓库 

## 代码风格
- 格式：无分号、两格缩进、单引号、末尾无句号
- 变量：不可变用 `const`
- 三元：多行编写
- 导出：避免 `export default`，用 `export const/function` 具名导出，可创建 `**/index.ts` 统一导出，可以 `export * from 'xx'`
- 类型：类型定义放在底部，确保不影响代码阅读
- 分组：同类逻辑用空行分块，避免密密麻麻；多换行，保持呼吸感
- 避免不必要的抽象层

## 代码质量
- 设计原则：SRP、OCP、LSP、ISP、DRY、KISS、避免硬编码
- 类型：严格 TS 类型，能用字符串字面量就别用 `string`，导出的 `type`/`interface` 提供 JSDoc（含 `@default`），TS 中 JSDoc 无需类型信息
- 运行 TS：`bun run /path/xx.ts`

## 组件设计
- 避免硬编码：通过 props/slots/children 暴露可变部分
- 单一职责：只负责 UI 渲染与交互，不掺杂业务数据/状态管理
- 最大化可控性：插槽、回调、受控模式
- 无副作用：不直接操作 DOM/全局状态/路由，依赖通过 props 注入
- 样式：TailwindCSS，支持 className/style 覆盖
- 组合优于继承
- 动画：自然流畅 motion/react(React) | motion-v(Vue)，UI 简洁冷静（参考 Vercel、Grok、Lovable）

## 文档撰写
- 代码即文档：函数加文档注释，复杂逻辑说明流程，文件开头说明作用
- 文本格式：英文用空格隔开，markdown 特殊词用斜体、重点加粗、两格缩进
- 语言：永远中文回答（除非明确要求其他语言），搜索优先英文
- 安全：私密数据放环境变量并提示用户填写

## 交互
- 获取 Web: 若有更好方式（如 MCP、WebFetch、已有可用内容等）可不使用 jina；否则可用 `curl "https://r.jina.ai/https://www.example.com" -H "Authorization: Bearer $JINA_KEY"`，它会返回干净的 Markdown

## Skill / Agent 自动调用
**处理以下情况时，必须先调用对应 Skill 或 Agent 再执行，不得跳过**

| 情况 | 类型 | 名称 |
|------|------|------|
| 编写 React（组件、Hooks、TSX、JSX 等） | Skill | `react` |
| 编写 Vue（组件、SFC、组合式 API 等） | Skill | `vue` |
| 编写 UI 设计（html、tsx、jsx、vue 页面/样式） | Skill | `ui-design` |
| 检测/审查当前 git 变更中的 i18n、多语言一致性 | Skill | `i18n` |
| 调试复杂 Bug、日志采集、运行时上下文收集 | Skill | `debug` |
| 前端布局（高度传递、定高管理、flex/grid 结构） | Skill | `layout` |
| 响应式布局（mobile-first、断点适配） | Skill | `responsive` |
| 浏览器查询等数据获取、自动化操作 | Skill | `playwright-cli` |
| 查询或操作 GitHub（仓库、文件、分支、Issue/PR） | Skill | `github` |
| 查文档、搜代码示例、联网检索 | Skill | `search` |
| 代码审查、重构、优化代码 | Skill | `code-review` |
| 提交代码（commit / push / git ci） | Skill | `commit` |


## 开发流程规范
1. **优先读 AGENTS.md / CLAUDE.md**：项目根目录或子目录出现这类约定文件时，下手前必须读完，不要凭印象做事
2. **以证据为准，不靠猜测**：API 行为、库能力、文件路径、配置语义都要查实。未证实前不说「可以/已支持」；区分「已改」与「已验证」——未跑过的代码不说「改好了」「已实现」，明确标注待用户验证
3. **先评估可行性再动手**：架构上做不到的事不要硬改 hook / monkey-patch；实现前先确认目标可达，不确定一定先问用户，避免最后一场空还污染代码
4. **调研先行**：不 100% 确定的技术点 / 库用法 → 必须先 `search` skill；GitHub 为主的项目 → 必须先 `github` skill；大型项目深度学习 → 克隆下来读源码
5. **用户自测**：完成代码改动后，如果方便测试，必须自动调用 `how-to-test` skill，告知用户如何测试，不得跳过（纯文档/注释改动除外）
6. **不主动改动 git 状态**：未经明确要求，禁止执行任何会改写工作区/暂存区/提交历史的 git 命令——`add`/暂存、`commit`、`push`、`reset`、`restore`、`checkout`/`switch`（丢弃改动）、`stash`、`rm`、`clean`、`merge`/`rebase`、删分支等。只读命令（`status`/`diff`/`log`/`show`）随意。需要写操作时先问、或只给出命令让用户自己跑；即便用户要求「提交」，也只处理已暂存内容，不擅自 `git add` 其它文件
7. 不确定时用 `// @TODO` 占位或提问，禁止编造函数/API，优先检索英文资料
8. **优先使用 LSP MCP 探索代码**：如果 `lsp-mcp` 可用，定位符号、定义、引用、调用关系、类型信息、诊断、重命名等操作时优先使用它；在 LSP 不适用、无结果或需要查看配置与文本内容时再使用文件搜索等工具
