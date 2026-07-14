---
name: worktree
description: 由用户主动调用，用于多功能并行开发
---

## 强制规则
**功能开发 / 并行任务禁止直接在当前分支改代码**，须在 worktree 完成（改 typo、文档等琐碎改动可豁免）

## 创建流程
1. **确保忽略**：项目 `.gitignore` 没有 `.worktrees/` 就加一行
   （否则主仓库 `git status` 冒 `?? .worktrees/`，`git add -A` 会把它当嵌入仓库误暂存）
2. **取最新基线**：`git fetch origin`
3. **建 worktree**：
   - 新分支：`git worktree add .worktrees/<name> -b <type>/<short-desc> origin/main`
   - 分支已存在：`git worktree add .worktrees/<name> <type>/<short-desc>`（不加 `-b`）
4. **初始化环境**（worktree 无 node_modules / 构建产物）：
   - 按 lock 文件选包管理器：`pnpm install` / `bun install` / ...
   - 需要构建产物的项目（包间依赖、需 dist 才能跑）再 `pnpm build`；纯 dev / 测试可跳过
5. 在 `.worktrees/<name>` 下完成改动，完成后告知用户**分支名 + worktree 路径**

## 命名
- 分支：`<type>/<short-desc>`（如 `fix/share-auth`）
- 目录：分支简写（如 `share-auth`）

## 完成清理
合并后回收：
- `git worktree remove .worktrees/<name>`（有未提交改动会拒绝，确认后 `--force`）
- `git worktree prune`

## 提示
- worktree 共享同一份 `.git`，不重下历史；贵的是环境，靠包管理器自身缓存省
  （pnpm 全局 store 硬链，install 通常很快），**别 `cp -r` node_modules**（硬链接会被复制成实体、绝对软链失效）
- 同一分支不能在两个 worktree 同时 checkout（git 限制）
