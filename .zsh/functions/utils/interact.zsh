# Interactive helpers (TTY-dependent)

# y/N confirmation: confirm "Delete file?" && rm file
confirm() {
  is_tty || return 1
  local reply
  read -q "reply?$1 [y/N] " || true
  echo >&2
  [[ ${reply:l} == y ]]
}
