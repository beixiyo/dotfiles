---
name: codex-delegate
description: 用户明确要求把任务派给 Codex（"丢给 codex"/"用 codex 跑一下"/"codex exec"/"codex 子 agent"）时使用。以本地 codex exec 作为隔离执行的子 agent：派发、续聊、回收、验收。用户没提 codex 时不主动派
---

## 分工

Claude 拆解任务、写 prompt、验收；codex 执行。codex 的汇报一律当"声称"，验收靠自己读 diff、跑命令

codex 是独立进程：读不到本会话对话，也问不了用户。依赖对话上下文的信息要写进 prompt；需要中途确认的任务不派

本机 `~/.codex/config.toml` 是 `approval_policy = "never"` + danger-full-access，没有审批兜底；
`--sandbox read-only` 会真拦写入（已实测），`workspace-write` 只靠 prompt 里的边界约束。敏感、破坏性、对外可见的操作不派

## 值不值得派

收益 = 规模 × 可并行度 × 上下文隔离

- 派：几十次工具调用的调研定位、模块级批量机械改动、彼此独立可同时跑的子任务、验收能靠 typecheck / 测试 / 构建兜住的编码
- 不派：单点小改（固定验收成本吃掉收益）、只能靠人读才判断得了好坏的（命名、API 设计、架构取舍、文案）

## 派发

入口是 `scripts/codex-run.sh`。它内建了关 stdin、脱离 Bash 工具 10 分钟上限、超时、心跳、进程组清理、完成判定、session_id 落盘。
不要手搓 `codex exec`；确有必要时先读 `references/manual-exec.md`

```bash
CR=~/.claude/skills/codex-delegate/scripts/codex-run.sh
RUN=<scratchpad>/codex-run-<n>; mkdir -p "$RUN"
cat > "$RUN/prompt.txt" <<'PROMPT'
...
PROMPT

"$CR" start --run-dir "$RUN" --agent <name> --sandbox <read-only|workspace-write> \
  --cwd <目标目录> --prompt-file "$RUN/prompt.txt" --timeout <秒> [-- <codex 额外参数>]
"$CR" status --run-dir "$RUN"   # 心跳快照；stalled=true 是「卡死」而非「慢」的信号
"$CR" wait   --run-dir "$RUN"   # 阻塞到终态，可反复调用；预计超 10 分钟的用 run_in_background
"$CR" result --run-dir "$RUN"   # 成功才打印答复，否则 exit 1 并带失败原因
"$CR" cancel --run-dir "$RUN"
```

- `--agent <name>` 读 `~/.codex/agents/<name>.toml`（以目录当前文件为准），自动带上 model / effort / developer_instructions，`--model` `--effort` 可单独覆盖。
  当前三档：`spark_xhigh` 窄范围机械改动、最便宜；`luna_high` 范围明确的编码 / 定点分析 / review；`luna_max` 跨模块根因、高风险语义判断
- 续聊 `--resume "$(cat "$RUN/session_id")"`，试探性分叉 `--fork <id>`（不污染原会话）；其余参数照传，`--cwd` 不能漏。纠正上一轮用 resume，不另开一轮从零讲
- 目标目录不是 git 仓库加 `-- --skip-git-repo-check`；跨仓 `-- --add-dir <dir>`；要结构化答复 `-- --output-schema <file>`
- prompt 只走 heredoc 文件（定界符加单引号），不内联进命令行：反引号和 `$` 会被 shell 静默吃掉，codex 收到残缺指令且无报错
- 多个独立任务各用一个 run-dir 同时 start，再逐个 result
- stderr 出现 `ERROR: You've hit your usage limit` 就换 agent，不对同一模型重试

## prompt 怎么写

按任务取舍，不必每段都有；每条要求可判定是唯一标准

- 目标与现场：症状、涉及的 file:line、仓库里已经写对的同类实现（给了参照它就不会自己发明）
- 边界：只准改哪些文件、不许动什么、对外签名不许变、禁止 git 写操作。实测它会顺手改没点名的行，这段越具体越好
- 本仓规范里的强制项：缩进、引号、注释语言与标点
- 验证：该跑的命令和当前基线数字（如「vitest 当前 402 passed，不许新增失败」）。派发前确认基线是当前值、构建产物已重建，否则它验的是旧东西
- 给判定依据，不给预判的结论：写死预期等于把自己的误判一起派下去。要求「预期与依据冲突时报告冲突，而不是迎合」
- 用到浏览器的任务要求收尾关闭，否则残留 profile lock，后续报 `Browser is already in use`

## 回收与验收

- `result` 通过 = exit 0 且 answer.md 非空且事件流有 `turn.completed` 且 stderr 无 `ERROR:`；任一不满足按未完成处理，不拿半截结果往下走
- 读它实际改的文件（`git diff`），不只看文字汇报；它说全部通过时，核心结论至少亲手复验一两条
- `git status --porcelain` 核对越界文件，检查残留进程（浏览器、dev server）
- codex 没跑成（失败、超时、空输出）时如实上报，问用户重试还是自己做；不要自己做完再当 codex 的结论汇报——委派的价值是拿到第二份独立意见
