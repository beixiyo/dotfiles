#!/usr/bin/env bash
# context.sh — 提取通知正文（AI 标题 + 最后一次用户输入）
# 被 main.sh source，不可单独执行

# _extract_context <optional_context_override>
# 若 $1 非空则直接用；否则尝试从 stdin 读取 Claude Stop hook JSON 并解析 transcript
# echo 最终 _body 字符串（上下文 或 fallback "回复完成，点击跳转"）
_extract_context() {
  local _context="${1:-}"

  if [[ -z "$_context" ]] && [[ ! -t 0 ]]; then
    local _hook_json _transcript _title _last
    _hook_json=$(cat 2>/dev/null)
    _transcript=$(printf '%s' "$_hook_json" | jq -r '.transcript_path // empty' 2>/dev/null)

    if [[ -f "$_transcript" ]]; then
      # ai-title：AI 生成的会话标题
      _title=$(grep '"type":"ai-title"' "$_transcript" | tail -1 \
        | jq -r '.aiTitle // empty' 2>/dev/null | tr -d '\n')
      # last-prompt：最后一次用户输入（截取前 50 字）
      _last=$(grep '"type":"last-prompt"' "$_transcript" | tail -1 \
        | jq -r '.lastPrompt // empty' 2>/dev/null | tr -d '\n' | cut -c1-50)

      if [[ -n "$_title" ]] && [[ -n "$_last" ]]; then
        _context="${_title}"$'\n'"${_last}"
      elif [[ -n "$_title" ]]; then
        _context="$_title"
      elif [[ -n "$_last" ]]; then
        _context="$_last"
      fi
    fi
  fi

  printf '%s' "${_context:-回复完成，点击跳转}"
}
