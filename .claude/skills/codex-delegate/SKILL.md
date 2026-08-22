---
name: codex-delegate
description: >
  当用户要求把任务派发/委派给 Codex、提到"丢给 codex"/"codex 子agent"/"用 codex 跑一下"/"codex exec"等，
  或需要用本地 Codex CLI 作为便宜的执行子agent时使用。负责拆解任务、按范围选 profile、拼 prompt、多轮续聊、
  回收结果并验收，不代劳最终验证
  收益随「规模 × 可并行度 × 上下文隔离」上升，最划算的是：要几十次工具调用的调研定位与资料汇总、
  模块级批量机械改动、彼此独立可同时跑的子任务——它们的原始输出不进主 context，验收只需读结论加抽查关键引用
  产出代码的任务再看验收能否机器化：typecheck / 测试报红 / lint / 构建失败能兜住就派；
  只能靠人读才判断得了好坏的（注释质量、命名、API 设计、架构取舍、文案）自己写更快
  最不划算的是单点小改动又手上无事可并行：验收成本固定，会吃掉大半收益；
  三种情况直接不要用——用户没明确要求委派时不主动派；任务依赖本会话的对话上下文、
  或过程中需要跟用户来回确认（codex 是独立进程，读不到对话也问不了人）；
  敏感、破坏性或对外可见的操作（本机 approval_policy 为 never，无审批与沙箱兜底）
---

## 定位

Claude 是派发方 + 规划方 + 最终验收方；`codex exec` 是执行方。Codex 的输出永远是"它声称完成了"，不是"已验证"——回收结果后必须自己读文件/跑测试确认，不满足就在同一 session 里继续纠正

`~/.codex/agents/*.toml` 里的 `agent_type`（luna_high/luna_max/spark_xhigh）是 Codex **内部**委派机制的参数，不是 `codex` CLI 对外暴露的 flag（`codex exec --help` 没有 `--agent-type`）。要复用这三档，需要手动把 toml 里的 `model` / `model_reasoning_effort` / `developer_instructions` 拼进 CLI 调用里，见下文

## Profile 选择（对应 ~/.codex/agents/*.toml，实际内容以该目录当前文件为准）

| profile       | model               | effort | 适用场景                                                 | 成本注记     |
| ------------- | ------------------- | ------ | -------------------------------------------------------- | ------------ |
| `spark_xhigh` | gpt-5.3-codex-spark | xhigh  | 范围极窄、验收明确的纯编码机械修改、快速迭代             | 最便宜最快的 |
| `luna_high`   | gpt-5.6-luna        | high   | 范围明确、可独立交付的编码/定点分析/常规 review          | 中等开销     |
| `luna_max`    | gpt-5.6-luna        | max    | 跨模块根因、高风险语义判断、需要深度推理且有明确收敛条件 | 开销最大     |

⚠️ 实测遇到过 `ERROR: You've hit your usage limit for GPT-5.3-Codex-Spark`。遇到限额报错则换模型用，不要对同一模型反复重试

## 首轮派发

prompt 是**两段式**：上半段是身份约束（谁在干活、守什么纪律），下半段才是这次的具体需求，中间用 `---` 隔开。

上半段要**原样抄** `~/.codex/agents/<profile>.toml` 里的 `developer_instructions`，一个字都不要改写。原因见「定位」：`agent_type` 是 codex 内部委派机制的参数，CLI 根本没有对应 flag，那份纪律不抄进 prompt 就完全不生效——codex 会退回默认行为，既不受"只改点名文件"约束，也不会按四项汇报。

```bash
codex exec \
  -m "<model>" \
  -c model_reasoning_effort="<effort>" \
  -C "<目标目录，默认当前项目根>" \
  -s workspace-write \
  --skip-git-repo-check \
  -o "<output_file>" \
  "<原样粘贴 ~/.codex/agents/<profile>.toml 的 developer_instructions>

---

任务：<见下方骨架>"
```

### 任务那半的骨架

```
## 缺陷 / 目标
症状是什么、根因在哪、涉及哪个文件哪一段。有 file:line 就给 file:line

## 对照实现（可选，但很管用）
仓库里已经写对的同类代码在哪。给了它就有参照，不必自己发明

## 要求
一条条列，每条都可判定。能复用的现成函数直接点名，别让它自己造

## 边界（严格遵守）
**只准改** 哪几个文件；哪些文件明确不许碰；哪些对外签名/行为不许变；
禁止 git 写操作；禁止改 .gitignore / package.json

## 代码规范
本仓强制项照抄进去（缩进、引号、注释语言与标点、JSDoc 位置）

## 验证
把它该跑的命令和当前基线数字写死，例如「`npx vitest run` 当前基线 402 passed / 0 failed，
改完不许出现任何新失败」
```

边界那段写得越死越好——实测它会顺手改没点名的行（见「已知行为特征」）。规范那段写了也常被忽略，但写了至少第二轮能拿它说事

- 纯只读分析/审查用 `-s read-only`（已实测真会拦写入，报 `patch rejected: writing is blocked by read-only sandbox`）；要改文件才用 `-s workspace-write`
- 这台机器全局 `approval_policy = "never"` 且 `default_permissions = ":danger-full-access"`，即没有审批和沙箱兜底，任务描述里的边界必须写清楚
- 涉及 `git commit/push/reset` 等操作，除非用户明确要求，否则在 prompt 里显式禁止
- `--skip-git-repo-check` 只在目标目录不是 git 仓库时才需要（比如临时用 scratchpad 目录测试）；派给项目内的真实任务可以省略

## 多轮续聊

```bash
codex exec resume --last \
  -m "<同一 model>" -c model_reasoning_effort="<同一 effort>" \
  --skip-git-repo-check \
  -o "<output_file>" \
  "<下一步指令，比如纠正/追问/补充验收标准>"
```

- **必须重新传 `-m`/`-c`**：`resume` 和 `fork` 都一样，不带这两个 flag 会掉回默认模型，且没有报错、只有一行warning，容易被忽略（已实测复现，两条命令都测过）
- 用具体 `session_id` 替代 `--last` 可以精确指定要续的会话（并行派发多个任务时避免接错）
- 需要在不污染原会话的前提下试探性分叉，用 `codex exec fork <session_id> -m "<model>" -c model_reasoning_effort="<effort>" "..."` 代替 resume；已实测 fork 出的分支不会污染原 session（原 session 之后 resume 仍能拿到 fork 之前的正确状态）

## 回收结果

- 优先读 `-o` 落盘的文件（Read 工具）：只有最终一条回复的纯文本，没有 session 头信息和 hook 日志噪音，适合直接当子agent报告用
- **`-o` 只在成功完成时写入**：调用失败（比如撞用量限制、sandbox 拒绝导致整轮报错）时 `-o` 文件不会被创建。回收前先看 stdout/exit code 里有没有 `ERROR:`，不要直接假设 `-o` 文件一定存在（已实测复现：spark 撞配额时进程仍返回，但 `-o` 文件没生成）
- 需要中间过程（工具调用、推理片段）时改用 `--json`，逐行是独立 JSON。已实测事件结构：`thread.started` → 若干 `item.completed`（`item.type` 可能是 `agent_message`/`error`/工具调用等）→ `turn.completed`
- **坑**：非交互 shell 里跑 `codex exec` 时，stdout 第一行常常是纯文本 `Reading additional input from stdin...`（不是 JSON），直接喂给 `jq` 会报 `Invalid numeric literal`（已实测复现）。用 `grep '^{'` 先过滤掉非 JSON 行，再提取最终文本：
  ```bash
  grep '^{' file.jsonl | jq -rs '[.[] | select(.type=="item.completed" and .item.type=="agent_message")] | last | .item.text'
  ```
- 不加 `-o` 时结果混在 stdout 里，Bash 工具会把 codex 子进程的 stdout/stderr 整体作为该次调用的返回值给到 Claude；能用就用 `-o`，减少噪音

## 并行派发

多个独立子任务用多次 Bash `run_in_background: true` 各自起一个 `codex exec`，各自指定不同的 `-o` 文件，之后逐个 Read 回收，等价于并行跑多个子agent（已实测两个并行任务各自的 `-o` 结果互不串）

## 验收纪律

1. 读 codex 实际改过的文件（Read / `git diff`），不要只看它的文字汇报
2. 不满足验收标准时，在同一 session `resume` 纠正，而不是另开一轮从零重讲上下文
3. 不确定要不要把某个任务（尤其敏感/破坏性任务）委派给 codex 时，先问用户，不要默认丢过去
