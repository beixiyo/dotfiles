#!/usr/bin/env bash
# context.sh — 提取通知正文（会话标题 + 最后一次用户输入 / 待确认的工具调用）
# 被 main.sh source，不可单独执行
#
# 支持的 transcript：
#   Claude Code：jsonl 内的 ai-title / last-prompt 记录
#   Codex：rollout jsonl（首行 session_meta）的 UserMessage；标题来自 ~/.codex/session_index.jsonl 的 thread_name

_CONTEXT_PROMPT_MAX=50
_CONTEXT_TOOL_MAX=80

# _extract_context <optional_context_override>
# 若 $1 非空则直接用；否则用 main.sh 已读入的 $_hook_json（stdin hook JSON）：
#   .context 优先（pi 扩展已拼好）→ 否则「标题 + 第二行」，第二行：带 tool_name（权限确认 / 提问）取工具摘要，否则取最后一次输入
# echo 最终 _body 字符串（上下文或英文 fallback）
_extract_context() {
  local _context="${1:-}"

  if [[ -z "$_context" && -n "${_hook_json:-}" ]]; then
    _context=$(printf '%s' "$_hook_json" | jq -r '.context // empty' 2>/dev/null)
  fi

  if [[ -z "$_context" && -n "${_hook_json:-}" ]]; then
    local _transcript _title="" _second
    _transcript=$(printf '%s' "$_hook_json" | jq -r '.transcript_path // empty' 2>/dev/null)
    _second=$(_context_tool_summary)

    if [[ -f "$_transcript" ]]; then
      if _is_codex_transcript "$_transcript"; then
        _title=$(_codex_title "$_transcript")
        [[ -n "$_second" ]] || _second=$(_codex_last_prompt "$_transcript")
      else
        _title=$(_claude_title "$_transcript")
        [[ -n "$_second" ]] || _second=$(_claude_last_prompt "$_transcript")
      fi
    fi

    _context=$(printf '%s\n%s' "$_title" "$_second" | sed '/^$/d')
  fi

  printf '%s' "${_context:-Response complete. Click to return.}"
}

# _context_tool_summary: PermissionRequest / PreToolUse 的“要做什么”，单行截断；无 tool_name 输出空
# AskUserQuestion 取第一个问题；其余取 命令 / 路径 等主参数
_context_tool_summary() {
  printf '%s' "$_hook_json" | jq -r --argjson max "$_CONTEXT_TOOL_MAX" '
    def str: if type == "array" then join(" ") elif type == "string" then . else "" end;
    (.tool_input // {}) as $in
    | if (.tool_name // "") == "" then empty
      elif .tool_name == "AskUserQuestion" then ($in.questions[0].question // "Question")
      else
        (($in.command // $in.cmd // $in.file_path // $in.path // $in.url // $in.pattern // "") | str) as $arg
        | if $arg == "" then .tool_name else "\(.tool_name): \($arg)" end
      end
    | gsub("\\s+"; " ") | .[0:$max]
  ' 2>/dev/null
}

# _is_codex_transcript <path>: Codex rollout 首行是 session_meta
_is_codex_transcript() {
  head -1 "$1" 2>/dev/null | grep -q '"type":"session_meta"'
}

# _claude_title <transcript>: AI 生成的会话标题
_claude_title() {
  grep '"type":"ai-title"' "$1" | tail -1 | jq -r '.aiTitle // empty' 2>/dev/null | tr -d '\n'
}

# _claude_last_prompt <transcript>: 最后一次用户输入
_claude_last_prompt() {
  grep '"type":"last-prompt"' "$1" | tail -1 \
    | jq -r --argjson max "$_CONTEXT_PROMPT_MAX" '.lastPrompt // empty | gsub("\\s+"; " ") | .[0:$max]' 2>/dev/null
}

# _codex_title <rollout>: session_index.jsonl 里该会话最新的 thread_name（未命名则为空）
# 会话 id 取 rollout 首行 session_meta，不依赖 hook 的 session_id 字段
_codex_title() {
  local _index="${CODEX_HOME:-$HOME/.codex}/session_index.jsonl" _id
  [[ -f "$_index" ]] || return 0
  _id=$(head -1 "$1" | jq -r '.payload.id // empty' 2>/dev/null)
  [[ -n "$_id" ]] || return 0
  grep -F "\"id\":\"$_id\"" "$_index" | tail -1 | jq -r '.thread_name // empty' 2>/dev/null | tr -d '\n'
}

# _codex_last_prompt <rollout>: 最后一条 UserMessage 的文本（不含 AGENTS.md / environment_context 注入）
_codex_last_prompt() {
  grep '"type":"UserMessage"' "$1" | tail -1 \
    | jq -r --argjson max "$_CONTEXT_PROMPT_MAX" '
        .payload.item.content // [] | map(select(.type == "text") | .text) | join(" ")
        | gsub("\\s+"; " ") | .[0:$max]
      ' 2>/dev/null
}
