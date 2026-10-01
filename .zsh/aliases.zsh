# 仅当第三方命令存在时才设置对应别名，避免未安装时报错

# Docker
if command -v docker &>/dev/null; then
  alias dps='docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}"'
  alias dis='docker images'
fi
# 见 functions.zsh：dd 统一 Docker 操作面板

# WSL 调用宿主机 PowerShell
if command -v pwsh.exe &>/dev/null; then
  alias p='pwsh.exe -Command'
fi

# systemctl（Linux）
if command -v systemctl &>/dev/null; then
  alias sys='sudo systemctl'
fi

# Dir（内置/通用，无需检测）
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias mkdir="mkdir -p"

alias cc="claude"
alias oc="opencode"
cx() {
  local runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$UID}"
  local wayland_display="${WAYLAND_DISPLAY:-}"
  local socket
  local -a codex_env

  if [[ -z "$wayland_display" ]]; then
    for socket in "$runtime_dir"/wayland-*(N); do
      [[ -S "$socket" ]] || continue
      wayland_display="${socket:t}"
      break
    done
  fi

  if [[ -n "$TMUX" ]]; then
    codex_env+=("SSH_CONNECTION=${SSH_CONNECTION:-tmux}")
  fi

  if [[ -n "$wayland_display" && -S "$runtime_dir/$wayland_display" ]]; then
    codex_env+=(
      "XDG_RUNTIME_DIR=$runtime_dir"
      "WAYLAND_DISPLAY=$wayland_display"
      "XDG_SESSION_TYPE=wayland"
      "DISPLAY="
    )
  fi

  # 交互会话不走共享 app-server daemon：hook 由 daemon 执行时继承的是 daemon 启动时的环境，
  # TMUX_PANE 等指向旧 pane，tmux badge / 通知跳转会落错（上面补的 env 同样传不到）
  # 只看第一个参数：无子命令（含直接带 prompt / 选项）→ 前置；resume / fork → 跟在子命令后；其余子命令原样透传
  # 显式 --remote 连远程 app server 时不加
  local -a codex_args=("$@")
  if (( ! ${codex_args[(I)--remote*]} )); then
    case "$1" in
      resume|fork) codex_args=("$1" --no-daemon "${@:2}") ;;
      ''|-*) codex_args=(--no-daemon "$@") ;;
      agents|exec|e|review|login|logout|mcp|plugin|app-server|remote-control|app|completion|update|doctor|sandbox|debug|apply|a|queue|archive|delete|migrate-rollouts|unarchive|cloud|exec-server|features|help) ;;
      *) codex_args=(--no-daemon "$@") ;;
    esac
  fi

  command env "${codex_env[@]}" codex "${codex_args[@]}"
}

# safe-rm
if command -v safe-rm &>/dev/null; then
  alias rm='safe-rm'
fi

# ls 精简（多列、图标、目录优先）
if command -v lsd &>/dev/null; then
  alias ls='lsd -a --icon always --group-directories-first -h'
  alias ll='lsd -l -a --icon always --group-directories-first -h --total-size'
  # 需要 git 状态时用 llg（大仓库可能较慢）
  alias llg='lsd -l -a --icon always --group-directories-first -h --total-size --git'
fi
# lt 见 functions.zsh：树形列表，可传递归层级

# Tools
# playwright-cli（WSL 下需在 Windows 用户目录执行，避免 UNC 路径导致 EPERM）
if [[ "$isWSL" -eq 1 ]]; then
  alias playwright-cli='cd "$(wslpath "$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d "\r")")" && bunx playwright-cli'
fi

alias v='"$HOME/.local/bin/editor"'
command -v btop &>/dev/null && alias top='btop'
command -v fzf &>/dev/null && alias fzf='fzf --ansi'
command -v jq &>/dev/null && alias jq='jq -C'   # 终端下彩色输出
