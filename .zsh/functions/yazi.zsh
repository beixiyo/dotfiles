# q 快速进入目录，Q 退出；仅当 yazi 存在时定义
if command -v yazi &>/dev/null; then
  function y() {
    local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
    # 避免 yazi 使用 TERM_PROGRAM 判断终端导致 WSL + WezTerm 异常按键
    TERM_PROGRAM="" command yazi "$@" --cwd-file="$tmp"
    IFS= read -r -d '' cwd < "$tmp"
    [ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
    rm -f -- "$tmp"
  }
fi
