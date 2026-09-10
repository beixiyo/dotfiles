# 手搓 codex exec 与已知坑

只在 `codex-run.sh` 不适用时读。以本机 `codex exec --help` 为准

## 最小安全调用

```bash
codex exec -m <model> -c model_reasoning_effort='"<effort>"' \
  -c developer_instructions='"""
<纪律，多行>
"""' \
  -C <目标目录> -s <read-only|workspace-write> -o "$RUN/answer.md" --json \
  "$(cat "$RUN/prompt.txt")" < /dev/null > "$RUN/events.jsonl" 2> "$RUN/stderr.log"
```

- `< /dev/null` 必须：不关 stdin 可能永久等 EOF，进程活着但 CPU 不涨，`-o` 永不出现
  （[openai/codex#20919](https://github.com/openai/codex/issues/20919)、[#19945](https://github.com/openai/codex/issues/19945)）
- 后台跑并重定向到文件：Bash 工具 10 分钟硬上限会 `exit 143` 杀掉任务且 `-o` 不生成；stdout 也要到进程结束才可见
- `developer_instructions` 是合法 config 键，`-c` 值按 TOML 解析：多行用 `"""`，反斜杠要转义。
  `~/.codex/agents/*.toml` 的 `agent_type` 是 codex 内部委派参数，CLI 没有对应 flag
- `-p <name>` 会叠加 `~/.codex/<name>.config.toml`，能直接吃 agents toml 的结构（已实测），但 resume / fork 没有 `-p`
- 没有 `--timeout`，超时要自己实现；`--ephemeral` 不落 session

## resume / fork

```bash
cd <目标目录> && codex exec resume <session_id> -m <model> -c model_reasoning_effort='"<effort>"' \
  -c developer_instructions='"""..."""' -c sandbox_mode='"<mode>"' -o ... --json "<prompt>" < /dev/null ...
```

- 没有 `-C/--cd`、`-s/--sandbox`：用调用方 PWD，沙箱走 `-c sandbox_mode`。不先 cd 会在错误目录读写（实测从 `~` 发起时文件落到了 `~`，无报错）
- `-m` / `-c` 必须重传，否则静默掉回默认模型，只有一行 warning
  （[openai/codex#32061](https://github.com/openai/codex/issues/32061)）
- 指定具体 session_id 而不是 `--last`，并行时避免接错
- fork 出的分支不污染原 session，原 session 之后仍能 resume 到 fork 前的状态（已实测）

## 判完成

无 TTY 时 codex 可能 exit 0 而输出全空（[#19945](https://github.com/openai/codex/issues/19945)），所以要同时满足：
exit 0、`-o` 文件存在且非空、stderr 无 `^ERROR:`、`--json` 事件流有 `turn.completed`

- `-o` 只在成功时写：撞用量限制、沙箱拒绝整轮报错时不生成，回收前先看 stderr
- 事件流：`thread.started`（含 `thread_id`，即 session_id）→ 若干 `item.completed` → `turn.completed`
- `item.type == "error"` 不一定是失败：每轮开头有一条 under-development features 警告事件
- `codex exec` 会打一行纯文本 `Reading additional input from stdin...`（0.153.4 走 stderr，旧版在 stdout），喂 jq 前先 `grep '^{'`：

```bash
grep '^{' events.jsonl | jq -rs '[.[] | select(.type=="item.completed" and .item.type=="agent_message")] | last | .item.text'
```

## 浏览器残留

`Browser is already in use` 是 profile lock 没释放。错误提示里推荐的 flag 可能在当前版本不存在，以本机 `--help` 为准；
全局 `pkill` 是最后手段，会误杀别的任务的浏览器（[openai/codex#16085](https://github.com/openai/codex/issues/16085)）
