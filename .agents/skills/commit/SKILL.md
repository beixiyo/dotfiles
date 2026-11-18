---
name: commit
description: 用户要求 commit、commit pathspec、提交或 push 时使用。按指定的提交来源和路径执行，保持其他改动与暂存内容
---

## 提交来源

- 只说 commit / 提交：提交已暂存内容，不自动 add。暂存为空时说明现状；不能自行切换为提交工作区
- 说 `commit pathspec`：根据本次实际修改确定精确文件清单，提交这些路径的工作区版本，不先 add，不夹带其他路径的暂存内容
- 用户另有明确范围或来源要求时按其要求执行；授权已明确不重复确认。提交授权不包含 push

## Pathspec 直提

```bash
git commit -m "fix(scope): 简述修改" -- path/to/a path/to/b
```

- 路径只列本次任务所属文件，不用目录或通配符扩大范围；所有选项放在 `--` 前
- 保留其他路径在 index 中的内容，不执行 add、reset、stash、restore 来拼凑提交
- 此方式提交指定文件的工作区内容，也会更新这些指定路径的 index；不能描述成整个 index 完全不变
- pathspec 不能隔离同一文件中不同 AI 的修改。发现目标文件混有他人改动或提交前内容变化时，核对差异；无法分清归属才询问
- 未跟踪的新文件不能直接这样提交；如需纳入，说明限制并取得该文件的暂存授权，不擅自 add
- 不并行执行同一仓库的 Git 写操作；出现锁冲突时不删锁、不覆盖其他任务

## 执行与核对

1. 读近期 `git log`、`git status --short`；分别检查 HEAD → index 与 index → worktree
2. 常规提交审查 staged diff；pathspec 提交审查目标路径 HEAD → worktree，并确认路径外的 staged 内容应被保留
3. 按选定方式提交。多行信息可用带引号的 heredoc 或消息文件配合 `-F`，避免 shell 展开反引号与变量
4. 用 `git show --stat --oneline HEAD` 和 status 核对提交范围、遗留改动；报告提交号和必要验证缺口

## 提交信息

采用 Conventional Commits，语言与 scope 跟随仓库历史，无历史时中文：

`<type>(<scope>): <subject>`

标题简洁说明最终改动；正文只补原因、重要行为和兼容影响。有关联 issue 时使用 `Closes #123` / `Refs #123`，不填无意义模板
