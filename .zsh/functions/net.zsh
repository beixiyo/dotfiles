# Network tools

() {
  local dir="${${(%):-%x}:A:h}"
  _NET_BUN_PROCESS="$dir/bun/src/process.ts"
}

myip() {
  curl -s https://ipinfo.io | jq -r '"IP:       \(.ip)\nCity:     \(.city)\nRegion:   \(.region)\nCountry:  \(.country)\nOrg:      \(.org)"'
}

# Show listening TCP ports with fzf kill support
# Usage: ports [port] [--all]
ports() {
  require lsof || return 1

  local use_sudo=0 filter_port=""
  for arg in "$@"; do
    [[ "$arg" == --all ]] && use_sudo=1
    [[ "$arg" =~ ^[0-9]+$ ]] && filter_port="$arg"
  done

  local lsof_cmd=(lsof -iTCP -sTCP:LISTEN -P -n)
  [[ -n "$filter_port" ]] && lsof_cmd=(lsof -iTCP:$filter_port -sTCP:LISTEN -P -n)
  (( use_sudo )) && { sudo -v || return 1; lsof_cmd=(sudo "${lsof_cmd[@]}") }

  local lines
  lines=$("${lsof_cmd[@]}" 2>/dev/null | awk 'NR > 1 {
    split($9, a, ":")
    printf "%s\t%s\t%s\t%s\n", $2, $1, a[length(a)], $9
  }' | sort -t$'\t' -k3 -n -u)

  [[ -z "$lines" ]] && { echo "No listening ports${filter_port:+ on $filter_port}"; return 0 }

  if ! has fzf; then
    printf "PID\tCOMMAND\tPORT\tADDRESS\n"
    echo "$lines"
    return 0
  fi

  local selected
  selected=$(echo "$lines" | fzf -m --bind tab:toggle+down \
    --header "PID	CMD	PORT	ADDRESS │ Multi ⇥ │ Kill ↵" \
    --reverse | awk -F'\t' '{print $1}')

  [[ -z "$selected" ]] && return 0

  if has bun; then
    bun run "$_NET_BUN_PROCESS" kill ${=selected}
  else
    for pid in ${=selected}; do
      kill "$pid" 2>/dev/null && echo "Killed $pid" || echo "Failed to kill $pid"
    done
  fi
}
