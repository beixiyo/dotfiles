# 按需获取上游源码

调研时需要读上游源码才用。优先复用版本匹配的本地仓库，不修改用户已有仓库的分支或工作区

## 何时克隆

- 少量已知文件直接通过文件接口读取（GitHub 用 `github` skill）
- 需要跨文件搜索、追踪调用链时再克隆
- 默认只取最新快照；分析历史行为时才加深历史，不能拿最新快照当历史版本的证据
- 克隆下来的第三方代码默认只读。需要运行验证时（构建、安装依赖、跑测试）在这个临时目录里进行，先确认来源可信、读过会执行的脚本，不在用户的项目里运行

## 浅克隆（分支或 tag）

```bash
source_dir=$(mktemp -d "${TMPDIR:-/tmp}/feasibility-source.XXXXXX")
git clone --depth=1 --branch '<branch-or-tag>' '<repository-url>' "$source_dir/repo"
```

`--depth=1` 只取最新 commit，不含历史。`--branch` 只接受分支名或 tag，不接受 commit SHA

## 指定 commit

SHA 必须是完整 40 位。需要远端允许按 SHA 获取（GitHub 支持）：

```bash
git init "$source_dir/repo"
git -C "$source_dir/repo" remote add origin '<repository-url>'
git -C "$source_dir/repo" fetch --depth=1 origin '<full-sha>'
git -C "$source_dir/repo" checkout --detach FETCH_HEAD
```

失败时改为克隆包含该 commit 的分支（`--depth=50`），再 `fetch --deepen` 加深直到能 `checkout`

## 注意

- 超大仓库先考虑用文件接口只读需要的文件，不要为此克隆全部
- 仓库使用 Git LFS 且本机装了 git-lfs 时，克隆会下载大文件；只读代码时在命令前加 `GIT_LFS_SKIP_SMUDGE=1` 跳过（检出文件的每条命令都要加）
- 用 `git -C "$source_dir/repo" rev-parse HEAD` 记录实际 commit，便于复核结论
- 清理只删本次创建的临时目录，删除前核实完整路径，不使用通配符，不删共享或归属不明的副本
