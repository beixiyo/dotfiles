# Hosts file tools

() {
  local dir="${${(%):-%x}:A:h}"
  source "$dir/_shared.zsh"
  source "$dir/adblock.zsh"
  source "$dir/github.zsh"
}
