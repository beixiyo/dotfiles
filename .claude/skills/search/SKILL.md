---
name: search
description: 当需要查资料、找文档、搜代码示例或联网检索时使用。按问题类型路由到文档查询、GitHub 仓库/代码搜索或联网搜索，不直接产出长篇调研
---

# 搜索策略

作为搜索路由器：先判断问题类型，再选最合适的工具。避免一上来就用 Web Search；只有专用工具不合适、查不到，或明确需要强实时/新闻类信息时才用它

## 工具与场景

- context7-mcp：库/框架/SDK/CLI 的最新文档与代码示例。已知具体库、API、配置项、版本差异时首选
- github skill（gh CLI）：已知 owner/repo，要查仓库里的文件、分支，或找 Issue/PR
- gh-grep-mcp：不关心具体仓库，在 GitHub 海量仓库里按代码模式（literal/正则）搜真实用法与实现
- exa-mcp：联网搜索。教程、博客、报错信息、事实性问题
- Web Search：最后兜底。前述工具都无结果，或强实时/新闻类信息

## 使用要点

- 文档类：context7 查询通常分两步——先解析库名拿到 ID，再按 ID 查文档；工具名以 server 实际暴露的 schema 为准，不要凭记忆调。查不到再转 GitHub 源码/Issue 或联网搜索
- exa 搜索时用 objective 参数描述期望的排序目标与排除项，比裸 query 效果好；抓正文用 fetch 类工具
- 多步研究类工具（如 agent_run）成本远高于单次搜索/抓取，非必要不发起
- exa 是付费 API（免费档每月额度有限）：调不通先查额度（dashboard.exa.ai）或 rate limit（429 重试即可），不要盲重试
- MCP 工具未直接声明时（如 pi 的 codemode 模式），运行时用 searchTools / describeTool 发现真实工具名与参数，不要依赖记忆里的键名（server 改名、`-`/`_` 归一化都会让硬编码失效）
- 抓网页正文分工：普通网页用 exa fetch；GitHub discussions/PR/issue 等重 JS 渲染页用 jina（`curl "https://r.jina.ai/<url>"`），Exa fetch 对这类页面常只拿到框架页；不要用 jina 抓搜索引擎结果页（基本返回空），要搜就用 exa-mcp；登录墙或交互后才出现的内容用 playwright-cli
- 读取网页原文的通用兜底：`curl "https://r.jina.ai/<url>" -H "Authorization: Bearer $JINA_KEY"`

## 场景示例

- 「React Router v6 的 useNavigate 全部参数」→ context7
- 「Next.js 14 基于中间件的 JWT 鉴权整套示例」→ context7（指定版本）
- 「不知道看哪个仓库，想看大家怎么写 useEffect 清理」→ gh-grep：query `(?s)useEffect\(\(\) => {.*removeEventListener`，useRegexp: true，language: ['TSX']
- 「已知 vercel/next.js，看官方示例的中间件实现」→ github skill 查文件
- 「查 reactjs/react.dev 里 hydration 相关 Issue」→ github skill：gh issue list --repo … --search "hydration"
- 「TypeError: Cannot read properties of undefined (reading 'map') 怎么排查」→ exa 搜报错
- 「React 最新 Roadmap / 刚发布的版本变更」→ exa，查不到再 Web Search
- 「今天刚出的技术新闻/政策原文」→ 直接 Web Search（强实时场景）
