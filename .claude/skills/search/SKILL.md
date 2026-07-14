---
name: search
description: 当需要查资料、找文档、搜代码示例或联网检索时使用。负责选择 Context7 MCP、GitHub、gh-grep、search-mcp 或 Web Search，不直接产出长篇调研
---

# 搜索策略

作为搜索路由器：先判断问题类型，再选择最合适的工具。避免一上来就用 Web Search；只有专用工具不合适、查不到，或明确需要强实时/新闻类信息时，才使用 Web Search

## 工具与推荐使用场景

| 工具 | 作用 | 典型场景 |
|------|------|----------|
| **context7 MCP** | 获取库/框架/SDK/CLI 的最新文档与代码示例 | 已知具体库、API、配置项、版本差异、官方示例 |
| **github** (skill) | 查询 **GitHub 仓库/文件/分支/Issue/PR**（通过 gh CLI） | 已知仓库名、看源码、**找 Issue/PR**、仓库元信息 |
| **gh-grep-mcp** | 使用 Grep.app 在 GitHub 上按**代码模式（literal/正则）**搜索 | 找真实项目里的代码片段、用法模式、最佳实践实现，而不是自然语言问答 |
| **search-mcp** | 使用 Exa 的 **Web Search API** 进行联网搜索 | 教程、博客、报错信息、事实性问题、需要较新/较干净网页内容的通用检索 |
| **Web Search** | 通用联网搜索（最后手段） | 仅当 context7/github/gh-grep/search-mcp 都无结果或需强实时/新闻时使用 |

## 使用说明

### 文档类（API、语法、概念）
- 已知是某库、框架、SDK、CLI、API 的用法时，优先用 **context7 MCP**
- Context7 MCP 通常先 `resolve-library-id`，再 `get-library-docs`
- 如果 Context7 查不到对应文档，再考虑 GitHub 源码、Issue/PR 或搜索

### GitHub 类
- **github** (skill)：已知 `owner/repo` 或要查某个仓库里的**文件、分支、Issue、PR** 时，调用 **github skill**（内部使用 gh CLI）
- **gh-grep-mcp**：不知道/不关心具体仓库，只想「在大量 GitHub 仓库里按代码模式（literal/正则）搜索」时用，适合找真实项目里的代码示例和用法模式

### 联网与兜底
- 教程、报错信息、事实性/通用问题：优先 **search-mcp**（Exa Web Search）
- **Web Search**：仅在前述工具都找不到或明确需要最新/实时信息时使用
- 获取网页全文内容时，若有更好方式（如 MCP fetch、search-mcp 已返回可用内容等）可直接用；否则可用 jina 将 HTML 转为 Markdown：`curl "https://r.jina.ai/https://example.com"`，再基于返回的 Markdown 分析

## 场景示例（按真实问题选工具）

- **「React Router v6 里 useNavigate 的全部参数有哪些？」**  
  用 **context7 MCP** 查官方文档与示例代码

- **「我要在 Next.js 14 里做基于中间件的 JWT 鉴权，有没有一整套示例？」**  
  用 **context7 MCP**，指定 Next.js 对应版本，查「middleware + JWT」相关文档和代码示例

- **「不知道该看哪个仓库，只想看看大家实际怎么写 useEffect 清理事件监听？」**  
  用 `gh-grep-mcp` 的 **searchGitHub** 工具：`query` 填 `(?s)useEffect\\(\\(\\) => {.*removeEventListener`，**useRegexp: true**，**language: ['TSX']**（或加 `'JSX'`）筛选 TSX/JSX

- **「我已经知道是 vercel/next.js 这个仓库，想看官方示例里的某个中间件实现细节」**  
  调用 **github skill** 查看 `vercel/next.js` 仓库里的对应文件/目录

- **「想查 reactjs/react.dev 里和 hydration 报错相关的 Issue」**  
  调用 **github skill**，用 `gh issue list --repo reactjs/react.dev --search "hydration"` 等查 Issue

- **「线上报错：`TypeError: Cannot read properties of undefined (reading 'map')`，想看别人怎么排查/避免？」**  
  用 `search-mcp` 搜索该错误信息，优先看高质量的博客/问答/最佳实践文章

- **「想了解 React 最新的官方 Roadmap 或刚发布的 19 版本变更点」**  
  如果 Context7 查不到最新公告，优先用 `search-mcp`，不够再用 `Web Search` 查“最新新闻/博客”

- **「需要看今天刚出的某条技术新闻或政策原文」**  
  直接用 `Web Search`，这是典型「强实时性」场景

- **「读取 example.com」**  
  若有更好方式可不走 jina；否则可用 `curl "https://r.jina.ai/https://www.example.com" -H "Authorization: Bearer $JINA_KEY"`，它会返回干净的 Markdown
