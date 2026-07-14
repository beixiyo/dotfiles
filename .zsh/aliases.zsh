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
alias cx="codex"

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

command -v nvim &>/dev/null && alias v='nvim'
command -v btop &>/dev/null && alias top='btop'
command -v fzf &>/dev/null && alias fzf='fzf --ansi'
command -v jq &>/dev/null && alias jq='jq -C'   # 终端下彩色输出
