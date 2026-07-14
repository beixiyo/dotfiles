# 长命令完成通知（>= 10s）
# 走 zsh hook 直接发系统通知，绕过 tmux 对 OSC 序列的拦截

_notify_threshold=10
_notify_cmd_time=0
_notify_cmd_text=""

_notify_preexec() {
  _notify_cmd_time=$EPOCHSECONDS
  _notify_cmd_text="${1:0:80}"
}

_notify_precmd() {
  local code=$?
  (( _notify_cmd_time == 0 )) && return

  # 用户主动 C-c 中断，不通知
  (( code == 130 )) && { _notify_cmd_time=0; return; }

  local elapsed=$(( EPOCHSECONDS - _notify_cmd_time ))
  _notify_cmd_time=0
  (( elapsed < _notify_threshold )) && return

  # 交互式/编辑器程序退出不通知
  case "${_notify_cmd_text%% *}" in
    nvim|vim|vi|v|nano|emacs|hx|less|man|top|htop|btop|fzf|claude|opencode) return ;;
  esac

  local icon="✅"
  (( code != 0 )) && icon="❌"

  if [[ "$OSTYPE" == darwin* ]]; then
    osascript -e "display notification \"${_notify_cmd_text}\" with title \"${icon} 完成 (${elapsed}s)\"" &!
  elif command -v notify-send &>/dev/null; then
    notify-send -t 5000 "${icon} 完成 (${elapsed}s)" "${_notify_cmd_text}" &!
  fi
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec _notify_preexec
add-zsh-hook precmd _notify_precmd
