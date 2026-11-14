[[ -d /opt/homebrew/bin ]] && export PATH="/opt/homebrew/bin:$PATH"

typeset -U path PATH
path+=("$HOME/.local/bin")

[[ -d "$HOME/.kiri/bin" ]] && path+=("$HOME/.kiri/bin")

export PATH
