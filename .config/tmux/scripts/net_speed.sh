#!/usr/bin/env bash
# 网速显示：上下行任意一个超过 THRESHOLD 才显示，否则静默
THRESHOLD=$((30 * 1024))  # 30 KB/s
CACHE="/tmp/.tmux_netspeed"

get_bytes() {
  case "$OSTYPE" in
    linux*)
      awk -F'[: \t]+' 'NR>2 {
        iface = ($1 == "") ? $2 : $1
        rx_bytes = ($1 == "") ? $3 : $2
        tx_bytes = ($1 == "") ? $11 : $10
        if (iface ~ /^(lo|docker|veth|br-|virbr|tun|vnet)/) next
        rx += rx_bytes; tx += tx_bytes
      } END { print rx+0, tx+0 }' /proc/net/dev
      ;;
    darwin*)
      netstat -ibn | awk '
      /:/ && !seen[$1]++ {
        if ($1 ~ /^lo/) next
        rx += $7; tx += $10
      } END { print rx+0, tx+0 }'
      ;;
    *)
      echo "0 0"
      ;;
  esac
}

fmt() {
  awk -v b="$1" 'BEGIN {
    if      (b >= 1073741824) printf "%.1fG", b / 1073741824
    else if (b >= 1048576)    printf "%.1fM", b / 1048576
    else if (b >= 1024)       printf "%.1fK", b / 1024
    else                      printf "%dB",   b
  }'
}

now=$(date +%s)
read -r cur_rx cur_tx < <(get_bytes)

if [[ -f "$CACHE" ]]; then
  IFS=' ' read -r prev_time prev_rx prev_tx < "$CACHE"
  elapsed=$(( now - prev_time ))

  if (( elapsed >= 1 )); then
    rx_bps=$(( (cur_rx - prev_rx) / elapsed ))
    tx_bps=$(( (cur_tx - prev_tx) / elapsed ))
    (( rx_bps < 0 )) && rx_bps=0
    (( tx_bps < 0 )) && tx_bps=0

    if (( rx_bps > THRESHOLD || tx_bps > THRESHOLD )); then
      c_bg=$(tmux show-option -gqv "@thm_bg")
      c_fg=$(tmux show-option -gqv "@thm_fg")
      c_sur=$(tmux show-option -gqv "@thm_surface_0")
      c_grn=$(tmux show-option -gqv "@thm_green")
      c_pch=$(tmux show-option -gqv "@thm_peach")
      printf " #[fg=%s,bg=%s] 󰇚 #[fg=%s,bg=%s] %s/s #[fg=%s,bg=%s] 󰕒 #[fg=%s,bg=%s] %s/s " \
        "$c_bg" "$c_grn" "$c_fg" "$c_sur" "$(fmt "$rx_bps")" \
        "$c_bg" "$c_pch" "$c_fg" "$c_sur" "$(fmt "$tx_bps")"
    fi
  fi
fi

printf '%s %s %s\n' "$now" "$cur_rx" "$cur_tx" > "$CACHE"
