---
name: commit
description: 用户要求提交代码（提到 "commit"/"提交"/"push"/"git ci" 等）时调用，生成符合 Conventional Commits、对齐本仓库既有风格的提交信息并执行提交
---

## 目标
完成一次干净的 git 提交：信息格式统一、语言与风格跟随本仓库、范围精确、带协作署名

## 前置（动手前必做）
1. `git log --oneline -10` —— 看本仓库 commit 的**既有语言**（中 / 英）与风格，对齐而非自创
2. `git status --short` + `git diff --staged --stat` —— 核对将要提交的文件范围
3. 仅在**用户明确要求**时 commit / push；未要求则只给命令或先问

## 提交信息格式（Conventional Commits）
`<type>(<scope>): <subject>`

- **type**：`feat`（新功能）/ `fix`（修 bug）/ `docs` / `style`（纯格式，不改逻辑）/ `refactor` / `perf` / `test` / `chore`（杂项 / 依赖）/ `build` / `ci` / `revert`
- **scope**：可选、小写，标明影响模块，如 `fix(nvim):`、`feat(loader):`
- **subject**：祈使句、简洁、≤ 50 字、结尾不加句号；语言**跟随仓库历史**（无历史则中文）

### 正文（改动稍大时才写）
- 与 subject 空一行隔开
- 用 `-` 列点说明**做了什么 + 为什么**，why 优先，不复述 diff 一眼能看到的细节
- 行宽约 72 字符

### Trailer
- 关联 issue 用 `Closes #123` / `Refs #123`

## 范围与暂存纪律
- 只提交与本次任务相关的文件，**不擅自 `git add` 无关改动**
- 用户说「提交」但暂存区为空 → 先确认要提交的文件集，再 `add`
- 用户已自行暂存 → 默认只提交已暂存内容，不擅自补 add 其它文件
- 危险 / 不可逆 git 操作（`reset` / `rebase` / `push -f` / `clean` 等）一律先确认

### 用户指定文件提交（pathspec 直提）
用户明确点名「只提交某几个改动 / 别动我的暂存区」时，用 **`git commit -- <路径…>`** 按路径直提，
取这些文件的**工作区版本**成一个 commit，**不碰 index 中其它已暂存内容**（也无需先 `git add`）：

```bash
git commit -m "标题" -m "正文" -- 文件1 文件2
```

- **选项必须写在 `--` 之前**：`--` 之后一律按路径解析，把 `-m`/`-F` 放到后面会报
  `pathspec '-m' did not match any file(s)`
- 长信息用 `-F -` 从 stdin 读，避免 heredoc 与 pathspec 混在一起：
  ```bash
  git commit -F - -- 文件1 文件2 <<'EOF'
  fix(scope): 标题

  - 说明
  EOF
  ```
- 适用：用户已有一批无关暂存改动，只想把本次任务的文件单独拎出来提交

## 分支
- 跟随仓库习惯：线性 `main` 历史的本地

## 执行步骤
1. 前置检查（`git log` / `status` / `diff`）
2. 归纳改动 → 选 type / scope → 写 subject（必要时加正文）
3. 选提交方式：
   - 常规 → `git add <精确文件>`（按需，范围含糊先问）后 `git commit`
   - 用户点名文件 / 要求别动暂存区 → `git commit -- <路径…>` 直提（见「用户指定文件提交」）
4. `git commit`（用 heredoc 写多行信息，带 trailer）
5. `git log --oneline -1` 回显结果；除非用户要求，**不自动 push**

## 示例
```
feat(vv-git): 仓库块显示分支、根仓库可折叠

- 标题行最前显示当前分支：彩色图标 + 分支名
- 根仓库可折叠：复用块折叠机制
```
