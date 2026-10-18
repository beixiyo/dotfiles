---
name: github
description: >-
  通过 gh CLI 查询 GitHub 上的信息：仓库元数据、源码文件、分支、提交、release 与 changelog、Issue、PR，也用于克隆或下载仓库做本地实验，以及用户明确要求时提 PR、建 Issue 等远端操作
  不必等用户给出仓库或链接：需要了解某个库的源码实现、已知问题与讨论、版本变更、维护状态，或找参考实现与同类项目时，应主动使用
  用户给出 owner/repo、GitHub 链接，或提到 issue、PR 时也使用
---

## 任务目标
使用 GitHub CLI (gh) 查询 GitHub 仓库信息、文件内容、提交记录、release、Issue 和 PR 等

不要等用户给出仓库或链接才用。遇到下面这些情况，自己判断并主动查，GitHub 上的一手信息往往比记忆和博客更可靠：
- 不确定某个库的行为或版本差异：读源码、看 release 和 changelog
- 遇到疑似库自身的 bug 或限制：搜 Issue 和 PR，看维护者是否已确认或已修复
- 评估依赖是否值得用：看 star、最近提交、最近 release、未关闭 Issue 的数量和类型
- 找参考实现或同类项目：搜仓库，再读关键文件
- 仓库名不确定时，先 `gh search repos` 定位，不要凭记忆猜 owner/repo

## 核心命令

### 仓库信息
```bash
# 建议优先使用 JSON 输出，避免 README 导致输出过长
gh repo view {owner}/{repo} --json name,description,primaryLanguage,stargazerCount,url
```

### 文件内容（最常用）
```bash
# 读取文件内容（需解码）
gh api "repos/{owner}/{repo}/contents/{path/to/file}" --jq '.content' | base64 -d

# 读取 README
gh api "repos/{owner}/{repo}/readme" --jq '.content' | base64 -d

# 列出目录（仅显示名称，节省 Token）
gh api "repos/{owner}/{repo}/contents/{path}" --jq '.[].name'
```

### 分支和提交
```bash
# 列出所有分支名称
gh api "repos/{owner}/{repo}/branches" --jq '.[].name'

# 获取最近 3 条提交记录（格式化输出）
gh api "repos/{owner}/{repo}/commits?per_page=3" --jq '.[] | {sha: .sha[0:7], message: .commit.message, author: .commit.author.name}'
```

### Issue 和 PR
```bash
# 列表显示（带限制）
gh issue list --repo {owner}/{repo} --limit 5
gh pr list --repo {owner}/{repo} --limit 5

# 搜索特定关键词的 Issue
gh issue list --repo {owner}/{repo} --search "{keyword}" --limit 5

# 获取 PR 详情（JSON）
gh api "repos/{owner}/{repo}/pulls/{number}" --jq '{title, body, state, html_url}'
```

### 搜索仓库、Issue 与 release
```bash
# 定位仓库（按 star 排序，限制数量）
gh search repos "{keywords}" --language {lang} --sort stars --limit 5 --json fullName,description,stargazersCount,updatedAt

# 跨仓库或指定仓库搜 Issue / PR（--repo 可省略做全站搜索）
gh search issues "{keywords}" --repo {owner}/{repo} --state open --limit 5 --json title,url,state,updatedAt
gh search prs "{keywords}" --repo {owner}/{repo} --limit 5 --json title,url,state

# 版本与 changelog
gh release list --repo {owner}/{repo} --limit 5 --exclude-pre-releases
gh release view --repo {owner}/{repo} [{tag}] --json tagName,publishedAt,body --jq '.body'
```

### 通用 API
```bash
gh api {endpoint} --jq '.field'              # 任意 API + jq 过滤
gh api -X POST {endpoint} -f key=value       # POST 请求
```

## 注意
- **必须对包含 `?` 或 `{}` 的 URL 加引号**，防止 Shell 错误
- **强制使用 `--jq` 过滤**：GitHub API 返回的原始 JSON 非常庞大，不加过滤会消耗大量 Token
- 文件内容是 base64 编码，必须配合 `| base64 -d` 使用
- 如果在本地仓库目录下，`{owner}` 和 `{repo}` 会被 `gh` 自动填充，但查询其他仓库时需手动替换
- **改动远端须用户明确要求**（如 gh repo edit、gh pr create / merge、gh issue create、评论、fork、push），执行前先确认目标仓库、内容和影响；查询类命令和 GET 请求直接用
- 克隆或下载到本地做实验、本地修改不受此限，但不要改动用户已有仓库的分支和工作区，克隆到新建的临时目录
- **搜索代码优先使用 `gh-grep-mcp`** 工具而不是 GitHub API
- `gh search repos` 返回 422（如 `User flagged as spammy`）时不要反复重试，改用无凭据的 `curl` 搜仓库，再用 `gh repo view` 验证；匿名请求额度很低（普通 API 60 次/小时，搜索 10 次/分钟），只作兜底，其余仍用 `gh`
  ```bash
  curl -sG "https://api.github.com/search/repositories" --data-urlencode "q={keywords} language:{lang}" -d sort=stars -d per_page=5 \
    | jq '.items[] | {full_name, description, stargazers_count}'
  ```
