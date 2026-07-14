# Colored log helpers (output to stderr)

if [[ -t 2 ]]; then
  _C_RED='\033[0;31m'
  _C_GREEN='\033[0;32m'
  _C_YELLOW='\033[0;33m'
  _C_CYAN='\033[0;36m'
  _C_DIM='\033[2m'
  _C_BOLD='\033[1m'
  _C_RESET='\033[0m'
else
  _C_RED='' _C_GREEN='' _C_YELLOW='' _C_CYAN='' _C_DIM='' _C_BOLD='' _C_RESET=''
fi

log()      { printf "${_C_CYAN}▸${_C_RESET} %s\n" "$*" >&2 }
log_ok()   { printf "${_C_GREEN}✔${_C_RESET} %s\n" "$*" >&2 }
log_warn() { printf "${_C_YELLOW}⚠${_C_RESET} %s\n" "$*" >&2 }
log_err()  { printf "${_C_RED}✘${_C_RESET} %s\n" "$*" >&2 }
log_dim()  { printf "${_C_DIM}%s${_C_RESET}\n" "$*" >&2 }
