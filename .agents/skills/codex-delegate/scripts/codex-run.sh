#!/usr/bin/env bash
#
# codex-run.sh —— codex exec 的生命周期包装器
#
# 解决手搓 codex exec 的四个问题：stdin 卡死、无进度、无超时、无法可靠判完成
# 用法见 SKILL.md「派发」一节
#
#   start   派发一轮，立即返回 run-dir
#           --agent <name> 读 $CODEX_HOME/agents/<name>.toml，把 model / effort /
#           developer_instructions 翻译成 -m / -c 传给 codex（start / resume / fork 通用）
#   status  打印心跳快照（活着 / 卡住 / 已结束）
#   wait    阻塞到终态
#   result  校验完成条件后打印最终答复
#   cancel  终止整个进程组
#
# 每轮的 session_id 落在 run-dir/session_id，续聊直接读它，不必去 events.jsonl 里捞
#
# 注意：中文串里的变量一律写 ${var}。bash 在 UTF-8 locale 下会把紧跟的多字节字符
# 并进变量名，`$st）` 会变成变量 `st）`，配合 set -u 直接报 unbound variable
set -uo pipefail

STALL_SECS="${CODEX_RUN_STALL_SECS:-180}"   # 事件流多久不动算卡住
POLL_SECS="${CODEX_RUN_POLL_SECS:-5}"

die() { echo "codex-run: $*" >&2; exit 2; }

now() { date +%s; }

# "MM:SS.ss" / "HH:MM:SS" → 秒
cpu_secs() {
  local raw; raw=$(ps -o time= -p "$1" 2>/dev/null | tr -d ' ')
  [ -z "$raw" ] && { echo -1; return; }
  echo "$raw" | awk -F: '{
    n = NF; s = 0; mult = 1
    for (i = n; i >= 1; i--) { s += $i * mult; mult *= 60 }
    printf "%d", s
  }'
}

write_state() { printf '%s\n' "$1" > "$RUN_DIR/state.tmp" && mv "$RUN_DIR/state.tmp" "$RUN_DIR/state"; }
read_state()  { cat "$RUN_DIR/state" 2>/dev/null || echo unknown; }

# agents/<name>.toml 是 codex 内部委派用的，CLI 没有对应 flag；这里把三个字段翻译成 -m / -c
# model / model_reasoning_effort 是单行字符串，developer_instructions 是 """ 多行块
load_agent() {
  local f="${CODEX_HOME:-$HOME/.codex}/agents/$1.toml"
  [ -f "$f" ] || die "找不到 agent 配置：$f"
  AGENT_MODEL=$(sed -n 's/^model *= *"\([^"]*\)".*/\1/p' "$f" | head -1)
  AGENT_EFFORT=$(sed -n 's/^model_reasoning_effort *= *"\([^"]*\)".*/\1/p' "$f" | head -1)
  AGENT_DI=$(awk '/^developer_instructions *= *"""/{f=1;next} f&&/^"""/{exit} f' "$f")
  # -c 的值按 TOML 解析：反斜杠是转义符要翻倍，三引号会提前闭合只能拒绝
  case "$AGENT_DI" in *'"""'*) die "agent ${1} 的 developer_instructions 含三引号，无法经 -c 传递" ;; esac
  AGENT_DI=${AGENT_DI//\\/\\\\}
}

# 续聊要用的 session_id：resume 轮也会重新播一条 thread.started，两种情况统一从事件流取
capture_session_id() {
  [ -s "$RUN_DIR/session_id" ] && return 0
  local sid
  sid=$(grep -m1 '"thread\.started"' "$RUN_DIR/events.jsonl" 2>/dev/null \
        | jq -r '.thread_id // empty' 2>/dev/null)
  [ -n "$sid" ] && printf '%s\n' "$sid" > "$RUN_DIR/session_id"
  return 0
}

# codex 的致命报错有两种形态：`ERROR: 用量超限` 和 `<时间戳> ERROR <模块>: ...`
# 它们不都意味着整轮失败（超时被杀时也会留下），所以只提示不参与判定
stderr_errors() { grep -aE '^ERROR:|[0-9]Z +ERROR ' "$RUN_DIR/stderr.log" 2>/dev/null; }

# ── 完成判定：退出码 0 单独不算成功
evaluate() {
  local exit_code="$1" reasons=()
  [ "$exit_code" -ne 0 ] && reasons+=("exit code $exit_code")
  [ -s "$RUN_DIR/answer.md" ] || reasons+=("answer.md 缺失或为空")
  if [ -s "$RUN_DIR/events.jsonl" ]; then
    grep -q '"turn\.completed"' "$RUN_DIR/events.jsonl" || reasons+=("事件流无 turn.completed")
  fi
  grep -q '^ERROR:' "$RUN_DIR/stderr.log" 2>/dev/null && reasons+=("stderr 出现 ERROR:")
  if [ ${#reasons[@]} -eq 0 ]; then echo ""; else printf '%s; ' "${reasons[@]}"; fi
}

# ══ 监工：心跳 + 超时。codex 进程消失或被杀时返回
cmd_supervise() {
  local codex_pid="$1" started deadline last_activity last_size
  started=$(now); deadline=0
  [ "${TIMEOUT_SECS:-0}" -gt 0 ] && deadline=$((started + TIMEOUT_SECS))
  last_activity=$started; last_size=0

  while kill -0 "$codex_pid" 2>/dev/null; do
    local size elapsed idle stalled
    size=$(wc -c < "$RUN_DIR/events.jsonl" 2>/dev/null | tr -d ' '); size=${size:-0}
    capture_session_id
    if [ "$size" -ne "$last_size" ]; then last_size=$size; last_activity=$(now); fi
    elapsed=$(( $(now) - started )); idle=$(( $(now) - last_activity ))
    stalled=false; [ "$idle" -ge "$STALL_SECS" ] && stalled=true

    cat > "$RUN_DIR/status.tmp" <<EOF
{"state":"running","pid":$codex_pid,"elapsed_secs":$elapsed,"idle_secs":$idle,
 "cpu_secs":$(cpu_secs "$codex_pid"),"events_bytes":$size,"stalled":$stalled,
 "last_event":"$(tail -1 "$RUN_DIR/events.jsonl" 2>/dev/null | jq -r '.type // "-"' 2>/dev/null || echo -)",
 "timeout_secs":${TIMEOUT_SECS:-0}}
EOF
    mv "$RUN_DIR/status.tmp" "$RUN_DIR/status.json"

    if [ "$deadline" -gt 0 ] && [ "$(now)" -ge "$deadline" ]; then
      echo "supervisor: 超时 ${TIMEOUT_SECS}s，终止进程组 $codex_pid" >> "$RUN_DIR/supervisor.log"
      kill_group "$codex_pid"
      write_state timed_out
      return
    fi
    sleep "$POLL_SECS"
  done
}

# codex 用工具跑起来的命令常常自成进程组（sandbox-exec 等），组杀打不到
# 趁父子链还在时递归快照一份后代 PID，组杀之后再补刀
descendants() {
  local p="$1" c
  for c in $(pgrep -P "$p" 2>/dev/null); do
    echo "$c"
    descendants "$c"
  done
}

# 先杀进程组，组内没杀干净再单杀，最后清理残留后代
kill_group() {
  local pid="$1"
  local -a tree=()
  while IFS= read -r c; do [ -n "$c" ] && tree+=("$c"); done < <(descendants "$pid")
  kill -TERM "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
  local i=0; while kill -0 "$pid" 2>/dev/null && [ $i -lt 10 ]; do sleep 1; i=$((i+1)); done
  if kill -0 "$pid" 2>/dev/null; then
    kill -KILL "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null
    sleep 1
  fi
  kill -0 "$pid" 2>/dev/null \
    && echo "supervisor: ★ 进程 $pid 仍未终止，需人工处理" >> "$RUN_DIR/supervisor.log" \
    || echo "supervisor: 进程组 $pid 已终止" >> "$RUN_DIR/supervisor.log"

  local c
  for c in "${tree[@]}"; do
    if kill -0 "$c" 2>/dev/null; then
      kill -KILL "$c" 2>/dev/null
      echo "supervisor: 清理残留后代进程 $c ($(ps -o command= -p "$c" 2>/dev/null | cut -c1-60))" \
        >> "$RUN_DIR/supervisor.log"
    fi
  done
}

cmd_start() {
  local model="" effort="" sandbox="read-only" cwd="$PWD" prompt_file="" resume="" fork="" timeout=0 agent=""
  AGENT_MODEL=""; AGENT_EFFORT=""; AGENT_DI=""
  local -a passthru=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --run-dir)     RUN_DIR="$2"; shift 2 ;;
      --agent)       agent="$2"; shift 2 ;;
      --model)       model="$2"; shift 2 ;;
      --effort)      effort="$2"; shift 2 ;;
      --sandbox)     sandbox="$2"; shift 2 ;;
      --cwd)         cwd="$2"; shift 2 ;;
      --prompt-file) prompt_file="$2"; shift 2 ;;
      --resume)      resume="$2"; shift 2 ;;
      --fork)        fork="$2"; shift 2 ;;
      --timeout)     timeout="$2"; shift 2 ;;
      --)            shift; passthru=("$@"); break ;;
      *)             die "未知参数 $1" ;;
    esac
  done
  [ -n "${RUN_DIR:-}" ] || die "缺 --run-dir"
  [ -n "$prompt_file" ] && [ -f "$prompt_file" ] || die "缺 --prompt-file 或文件不存在"
  [ -s "$prompt_file" ] || die "prompt 文件为空：$prompt_file"
  if [ -n "$agent" ]; then
    load_agent "$agent"
    [ -n "$model" ] || model="$AGENT_MODEL"     # 显式 --model / --effort 优先于 agent 文件
    [ -n "$effort" ] || effort="$AGENT_EFFORT"
  fi
  [ -n "$model" ] || die "缺 --model 或 --agent"
  command -v codex >/dev/null 2>&1 || die "PATH 里找不到 codex"
  [ -n "$resume" ] && [ -n "$fork" ] && die "--resume 和 --fork 只能给一个"
  [ -d "$cwd" ] || die "工作目录不存在：$cwd"

  # 复用 run-dir 会覆盖上一轮的 answer/events，正在跑的任务直接拦下
  if [ "$(cat "$RUN_DIR/state" 2>/dev/null)" = running ]; then
    local old_pid; old_pid=$(cat "$RUN_DIR/codex.pid" 2>/dev/null)
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
      die "run-dir 里还有在跑的任务（pid ${old_pid}），换个 --run-dir 或先 cancel"
    fi
  fi

  mkdir -p "$RUN_DIR"
  # prompt-file 直接指向 run-dir 时无需复制
  [ "$(cd "$(dirname "$prompt_file")" && pwd)/$(basename "$prompt_file")" = "$RUN_DIR/prompt.txt" ] \
    || cp "$prompt_file" "$RUN_DIR/prompt.txt"
  : > "$RUN_DIR/events.jsonl"; : > "$RUN_DIR/stderr.log"
  rm -f "$RUN_DIR/answer.md" "$RUN_DIR/session_id" "$RUN_DIR/exit_code" "$RUN_DIR/failure_reason" \
        "$RUN_DIR/status.json"

  local -a args=()
  [ -n "$resume" ] && args+=(resume "$resume")
  [ -n "$fork" ] && args+=(fork "$fork")
  args+=(-m "$model")
  [ -n "$effort" ] && args+=(-c "model_reasoning_effort=\"$effort\"")
  # developer_instructions 是合法 config 键且三种子命令都吃 -c（已实测），不必再抄进 prompt
  [ -n "$AGENT_DI" ] && args+=(-c "developer_instructions=\"\"\"
$AGENT_DI
\"\"\"")
  # resume / fork 子命令都没有 -s/--sandbox 和 -C/--cd（已实测）：
  # 沙箱只能走 -c；工作目录不会从原 session 继承，只能靠 worker 先 chdir 过去
  if [ -n "$resume" ] || [ -n "$fork" ]; then
    args+=(-c "sandbox_mode=\"$sandbox\"")
  else
    args+=(-s "$sandbox" -C "$cwd")
  fi
  args+=(-o "$RUN_DIR/answer.md" --json)
  [ ${#passthru[@]} -gt 0 ] && args+=("${passthru[@]}")
  args+=("$(cat "$RUN_DIR/prompt.txt")")

  cat > "$RUN_DIR/meta.json" <<EOF
{"agent":"$agent","model":"$model","effort":"$effort","sandbox":"$sandbox","cwd":"$cwd",
 "resume":"$resume","fork":"$fork","timeout_secs":$timeout,
 "codex_version":"$(codex --version 2>/dev/null | tr -d '\n')","started_at":"$(date -Iseconds)"}
EOF
  printf '%s\n' "$cwd" > "$RUN_DIR/cwd"
  : > "$RUN_DIR/args"
  local a; for a in "${args[@]}"; do printf '%s\0' "$a" >> "$RUN_DIR/args"; done
  write_state running

  # 监工与 codex 都要脱离调用方的生命周期
  nohup "$SELF" __worker "$RUN_DIR" "$timeout" >> "$RUN_DIR/supervisor.log" 2>&1 &
  disown 2>/dev/null

  echo "$RUN_DIR"
}

# 内部：detached 上下文里跑 codex + 监工
cmd_worker() {
  RUN_DIR="$1"; TIMEOUT_SECS="$2"
  local -a cargs=(); local a
  while IFS= read -r -d '' a; do cargs+=("$a"); done < "$RUN_DIR/args"

  # resume/fork 没有 -C/--cd，codex 直接用调用方的 PWD——不 chdir 就会在错误的仓库里动手
  local run_cwd; run_cwd=$(cat "$RUN_DIR/cwd" 2>/dev/null)
  if [ -n "$run_cwd" ] && ! cd "$run_cwd"; then
    echo "worker: 无法进入工作目录 $run_cwd" >> "$RUN_DIR/supervisor.log"
    printf '%s\n' "无法进入工作目录 $run_cwd" > "$RUN_DIR/failure_reason"
    write_state failed
    return
  fi

  # 必须内联 perl：包进函数再后台化的话，$! 拿到的是子 shell 而不是 codex 本体
  # perl 先 setpgrp 让自己成为组长，再 exec 成 codex —— PID 不变，于是 PID == PGID
  perl -e 'setpgrp(0,0); exec @ARGV or die "exec failed: $!\n"' -- \
    codex exec "${cargs[@]}" \
    < /dev/null > "$RUN_DIR/events.jsonl" 2> "$RUN_DIR/stderr.log" &
  local codex_pid=$!
  echo "$codex_pid" > "$RUN_DIR/codex.pid"

  cmd_supervise "$codex_pid"
  wait "$codex_pid" 2>/dev/null; local code=$?
  echo "$code" > "$RUN_DIR/exit_code"
  capture_session_id

  case "$(read_state)" in cancelled|timed_out) return ;; esac
  local failures; failures=$(evaluate "$code")
  if [ -z "$failures" ]; then write_state succeeded; else
    printf '%s\n' "$failures" > "$RUN_DIR/failure_reason"; write_state failed
  fi
}

cmd_status() {
  local st; st=$(read_state)
  echo "state: $st"

  case "$st" in
    running)
      # 只有 running 时快照才是当前值，终态下打出来会和 state 自相矛盾
      [ -s "$RUN_DIR/status.json" ] && jq -c . "$RUN_DIR/status.json" 2>/dev/null
      local s; s=$(jq -r '.stalled' "$RUN_DIR/status.json" 2>/dev/null)
      [ "$s" = "true" ] && echo "⚠️  事件流已 $(jq -r '.idle_secs' "$RUN_DIR/status.json")s 没有新内容，疑似卡住" ;;
    *)
      local el; el=$(jq -r '.elapsed_secs // empty' "$RUN_DIR/status.json" 2>/dev/null)
      [ -n "$el" ] && echo "耗时约 ${el}s，exit code $(cat "$RUN_DIR/exit_code" 2>/dev/null || echo -)"
      [ "$st" = failed ] && echo "失败原因: $(cat "$RUN_DIR/failure_reason" 2>/dev/null)" ;;
  esac

  [ -s "$RUN_DIR/session_id" ] && echo "session_id: $(cat "$RUN_DIR/session_id")  # 续聊用 --resume 传它"

  local errs; errs=$(stderr_errors | head -3)
  [ -n "$errs" ] && { echo "stderr 里的 ERROR（仅提示，不参与判定）:"; printf '  %s\n' "$errs"; }
  return 0
}

cmd_wait() {
  # 监工/codex 被外部杀掉时 state 会永远停在 running，这里自己判定，避免无限阻塞
  local gone=0
  while :; do
    case "$(read_state)" in running) ;; *) break ;; esac

    local pid; pid=$(cat "$RUN_DIR/codex.pid" 2>/dev/null)
    if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then
      gone=$((gone + 1))
    elif [ -z "$pid" ]; then
      gone=$((gone + 1))   # 迟迟没写出 pid，同样按异常计数
    else
      gone=0
    fi

    if [ "$gone" -ge 4 ]; then
      printf '%s\n' "codex 进程已消失但状态仍是 running（监工可能被杀），结果不可信" \
        > "$RUN_DIR/failure_reason"
      write_state failed
      break
    fi
    sleep "$POLL_SECS"
  done
  cmd_status
}

cmd_result() {
  local st; st=$(read_state)
  if [ "$st" != "succeeded" ]; then
    echo "codex 这轮未成功完成（state=${st}）。禁止拿自己的分析顶替，如实上报后再决定重试还是改由自己做。" >&2
    [ -s "$RUN_DIR/failure_reason" ] && echo "原因: $(cat "$RUN_DIR/failure_reason")" >&2
    [ -s "$RUN_DIR/stderr.log" ] && { echo "--- stderr 末尾 ---" >&2; tail -20 "$RUN_DIR/stderr.log" >&2; }
    exit 1
  fi
  cat "$RUN_DIR/answer.md"
  [ -s "$RUN_DIR/session_id" ] \
    && echo "--- 续聊 session_id: $(cat "$RUN_DIR/session_id") ---" >&2
  return 0
}

cmd_cancel() {
  local st; st=$(read_state)
  if [ "$st" != running ]; then
    echo "这轮已经是终态（state=${st}），不覆盖结果；无需取消"
    return 0
  fi
  local pid; pid=$(cat "$RUN_DIR/codex.pid" 2>/dev/null)
  write_state cancelled
  [ -n "$pid" ] && kill_group "$pid"
  echo "已请求终止进程组 ${pid}；详见 $RUN_DIR/supervisor.log"
}

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
sub="${1:-}"; shift || true
case "$sub" in
  start)     cmd_start "$@" ;;
  __worker)  cmd_worker "$@" ;;
  status|wait|result|cancel)
    [ "${1:-}" = "--run-dir" ] || die "用法: codex-run.sh $sub --run-dir DIR"
    RUN_DIR="$2"; "cmd_$sub" ;;
  *) die "用法: codex-run.sh {start|status|wait|result|cancel} ..." ;;
esac
