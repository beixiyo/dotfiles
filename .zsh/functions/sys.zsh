# System utilities

# Unified clipboard: pipe in -> copy, args -> copy string, no input -> paste
# Usage: echo "text" | cb / cb "text" / cb
cb() {
  if [[ -z "$_CLIP_COPY" ]]; then
    log_err "no clipboard tool found (pbcopy/xclip/xsel/wl-copy/clip.exe)"
    return 1
  fi

  if [[ ! -t 0 ]]; then
    tee >(eval "$_CLIP_COPY" 2>/dev/null)
  elif (( $# )); then
    echo -n "$*" | tee >(eval "$_CLIP_COPY" 2>/dev/null)
  else
    eval "$_CLIP_PASTE"
  fi
}

# System overview: OS / CPU / Memory / Disk / Uptime
# Color defaults to auto (TTY only); --color forces it, --no-color disables it
sysinfo() {
  local color_mode=auto
  case ${1:-} in
    --color) color_mode=always ;;
    --no-color) color_mode=never ;;
    '') ;;
    *)
      log_err "usage: sysinfo [--color|--no-color]"
      return 1
      ;;
  esac

  local label_color='' value_color='' reset_color=''
  if [[ $color_mode == always || ($color_mode == auto && -t 1 && -z ${NO_COLOR:-}) ]]; then
    label_color=$'\033[1;36m'
    value_color=$'\033[0;32m'
    reset_color=$'\033[0m'
  fi

  local os cpu memory disk uptime_seconds

  if is_mac; then
    os="$(sw_vers -productName) $(sw_vers -productVersion)"
    cpu=$(sysctl -n machdep.cpu.brand_string)
    local total_gb=$(( $(sysctl -n hw.memsize) / 1073741824 ))
    local used_gb=$(vm_stat | awk '
      /page size/        { ps = $8 }
      /Pages active/     { a = $3+0 }
      /Pages wired/      { w = $4+0 }
      /Pages speculative/ { s = $3+0 }
      /Pages occupied by compressor/ { c = $5+0 }
      END { printf "%.1f", (a + w + s + c) * ps / 1073741824 }
    ')
    memory="${used_gb} GB used / ${total_gb} GB"

    local disk_info
    disk_info=$(diskutil info / 2>/dev/null)
    local total=$(echo "$disk_info" | awk -F': +' '/Container Total Space/ {print $2}')
    local free=$(echo "$disk_info" | awk -F': +' '/Container Free Space/ {print $2}')
    disk="${total%% \(*} total, ${free%% \(*} free"

    local boot_epoch
    # 锚定开头的 sec，避免贪婪匹配误取后面的 usec
    boot_epoch=$(sysctl -n kern.boottime \
      | sed -E 's/^\{[[:space:]]*sec[[:space:]]*=[[:space:]]*([0-9]+),.*/\1/')
    if [[ $boot_epoch != <-> ]]; then
      log_err "unable to parse macOS boot time"
      return 1
    fi
    uptime_seconds=$(( $(date +%s) - boot_epoch ))
  else
    os=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
    cpu=$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)
    memory=$(free -h 2>/dev/null | awk '/Mem:/ {print $3 " used / " $2}')
    disk=$(df -h / | awk 'NR==2 {print $3 " used / " $2 " (" $5 ")"}')

    read -r uptime_seconds _ < /proc/uptime
    uptime_seconds=${uptime_seconds%%.*}
    if [[ $uptime_seconds != <-> ]]; then
      log_err "unable to parse Linux uptime"
      return 1
    fi
  fi

  local days=$(( uptime_seconds / 86400 ))
  local hours=$(( uptime_seconds % 86400 / 3600 ))
  local minutes=$(( uptime_seconds % 3600 / 60 ))
  local seconds=$(( uptime_seconds % 60 ))
  local uptime
  if (( days > 0 )); then
    printf -v uptime '%dd %02dh %02dm %02ds' $days $hours $minutes $seconds
  else
    printf -v uptime '%02dh %02dm %02ds' $hours $minutes $seconds
  fi

  printf '%b%-8s%b%b%s%b\n' "$label_color" 'OS:' "$reset_color" "$value_color" "$os" "$reset_color"
  if is_mac; then
    printf '%b%-8s%b%b%s%b\n' "$label_color" 'Chip:' "$reset_color" "$value_color" "$cpu" "$reset_color"
  else
    printf '%b%-8s%b%b%s%b\n' "$label_color" 'Kernel:' "$reset_color" "$value_color" "$(uname -r)" "$reset_color"
    printf '%b%-8s%b%b%s%b\n' "$label_color" 'CPU:' "$reset_color" "$value_color" "$cpu" "$reset_color"
  fi
  printf '%b%-8s%b%b%s%b\n' "$label_color" 'Memory:' "$reset_color" "$value_color" "$memory" "$reset_color"
  printf '%b%-8s%b%b%s%b\n' "$label_color" 'Disk:' "$reset_color" "$value_color" "$disk" "$reset_color"
  printf '%b%-8s%b%b%s%b\n' "$label_color" 'Uptime:' "$reset_color" "$value_color" "$uptime" "$reset_color"
}
