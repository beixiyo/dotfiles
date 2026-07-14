#!/usr/bin/env zsh

# Mihomo proxy node management (core logic in bun/src/mihomo.ts)
# Usage:
#   mihomo-nodes              list all nodes
#   mihomo-now                show current node
#   mihomo-set [node]         switch node (fzf select if no arg, with latency test by default)
#     --nofzf                   disable fzf, use index input
#     --no-test                 skip latency test
#   mihomo-test [node]        test latency (no arg = test all)

() {
  local dir="${${(%):-%x}:A:h}"
  MIHOMO_BUN_SCRIPT="$dir/bun/src/mihomo.ts"
}

mihomo-nodes() {
  require bun || return 1
  bun run "$MIHOMO_BUN_SCRIPT" nodes
}

mihomo-now() {
  require bun || return 1
  bun run "$MIHOMO_BUN_SCRIPT" now
}

mihomo-test() {
  require bun || return 1
  bun run "$MIHOMO_BUN_SCRIPT" test "$@"
}

mihomo-set() {
  require bun || return 1

  local name="" use_fzf=1 with_test=1
  for arg in "$@"; do
    case "$arg" in
      --nofzf)   use_fzf=0 ;;
      --no-test) with_test=0 ;;
      --test)    with_test=1 ;;
      *)         name="$arg" ;;
    esac
  done

  if [[ -z "$name" ]]; then
    local current selected
    current=$(bun run "$MIHOMO_BUN_SCRIPT" now) || return 1

    if (( use_fzf )) && has fzf; then
      if (( with_test )); then
        selected=$(bun run "$MIHOMO_BUN_SCRIPT" test-stream < /dev/null 2>/dev/null \
          | fzf --reverse --ansi --delimiter=$'\t' --nth=3.. \
                --header "Select node (current: $current) - testing latency...")
        [[ -z "$selected" ]] && return 0
        name="${selected##*$'\t'}"
      else
        local lines
        lines=$(bun run "$MIHOMO_BUN_SCRIPT" nodes < /dev/null) || return 1
        selected=$(awk -v cur="$current" '
          {
            if ($0 == cur) printf "\033[1;32m>\t%s\033[0m\n", $0
            else printf " \t%s\n", $0
          }' <<< "$lines" \
          | fzf --reverse --ansi --delimiter=$'\t' --nth=2.. \
                --header "Select node (current: $current)")
        [[ -z "$selected" ]] && return 0
        name="${selected#*$'\t'}"
      fi
    else
      local lines
      if (( with_test )); then
        log "testing node latency..."
        lines=$(bun run "$MIHOMO_BUN_SCRIPT" test) || return 1
      else
        lines=$(bun run "$MIHOMO_BUN_SCRIPT" nodes) || return 1
      fi
      echo "Current: $current"
      echo ""
      local i=1
      while IFS= read -r line; do
        printf "  %3d) %s\n" $i "$line"
        (( i++ ))
      done <<< "$lines"
      echo ""
      printf "Enter number: "
      local choice
      read -r choice
      [[ -z "$choice" || ! "$choice" =~ ^[0-9]+$ ]] && return 0
      selected=$(sed -n "${choice}p" <<< "$lines")
      [[ -z "$selected" ]] && { log_err "invalid number"; return 1; }
      if (( with_test )); then
        name="${selected#*$'\t'}"
      else
        name="$selected"
      fi
    fi
  fi

  bun run "$MIHOMO_BUN_SCRIPT" set "$name"
}
