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
sysinfo() {
  if is_mac; then
    echo "OS:     $(sw_vers -productName) $(sw_vers -productVersion)"
    echo "Chip:   $(sysctl -n machdep.cpu.brand_string)"
    local total_gb=$(( $(sysctl -n hw.memsize) / 1073741824 ))
    local used_gb=$(vm_stat | awk '
      /page size/        { ps = $8 }
      /Pages active/     { a = $3+0 }
      /Pages wired/      { w = $4+0 }
      /Pages speculative/ { s = $3+0 }
      /Pages occupied by compressor/ { c = $5+0 }
      END { printf "%.1f", (a + w + s + c) * ps / 1073741824 }
    ')
    echo "Memory: ${used_gb} GB used / ${total_gb} GB"
  else
    echo "OS:     $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')"
    echo "Kernel: $(uname -r)"
    echo "CPU:    $(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)"
    echo "Memory: $(free -h 2>/dev/null | awk '/Mem:/ {print $3 " used / " $2}')"
  fi
  if is_mac; then
    local disk_info
    disk_info=$(diskutil info / 2>/dev/null)
    local total=$(echo "$disk_info" | awk -F': +' '/Container Total Space/ {print $2}')
    local free=$(echo "$disk_info" | awk -F': +' '/Container Free Space/ {print $2}')
    echo "Disk:   ${total%% *} total, ${free%% *} free"
  else
    echo "Disk:   $(df -h / | awk 'NR==2 {print $3 " used / " $2 " (" $5 ")"}')"
  fi
  echo "Uptime: $(uptime | sed 's/.*up //' | sed 's/,.*load.*//' | xargs)"
}
