# Network tools

() {
  local dir="${${(%):-%x}:A:h}"
  _NET_BUN_PROCESS="$dir/bun/src/process.ts"
}

# AWAvenue-Ads-Rule 广告屏蔽 hosts 订阅镜像，按可靠性从高到低排列，逐个重试
_ADBLOCK_HOSTS_MIRRORS=(
  'jsDelivr|https://gcore.jsdelivr.net/gh/TG-Twilight/AWAvenue-Ads-Rule@main/Filters/AWAvenue-Ads-Rule-hosts.txt'
  'CFCDN proxy|https://github.boki.moe/https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/Filters/AWAvenue-Ads-Rule-hosts.txt'
  'ghproxy|https://ghfast.top/https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/Filters/AWAvenue-Ads-Rule-hosts.txt'
  'GitHub Raw|https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/Filters/AWAvenue-Ads-Rule-hosts.txt'
  'CXPLAY mirror|https://script.cx.ms/awavenue/AWAvenue-Ads-Rule-hosts.txt'
  'wangfugui mirror|https://cdn.uura.cn/AWAvenue/AWAvenue-Ads-Rule-hosts.txt'
)

# adblockHosts 托管区块的哨兵注释行：只替换标记之间的内容，标记外的系统/自定义条目原样保留
_ADBLOCK_HOSTS_BEGIN='# >>> adblockHosts BEGIN (managed, do not edit inside) >>>'
_ADBLOCK_HOSTS_END='# <<< adblockHosts END <<<'

# 拉取 AWAvenue-Ads-Rule 广告屏蔽 hosts（逐个镜像重试直到成功），合并进系统 /etc/hosts
# 只替换 BEGIN/END 标记之间的托管区块，标记之外的内容保持不变；首次运行会在文件末尾追加该区块（已自动备份一份）
# Usage: adblockHosts
adblockHosts() {
  require curl || return 1

  log_warn "This will update the adblockHosts-managed block in /etc/hosts; everything outside the markers is left untouched"
  confirm "Proceed?" || { log "Cancelled"; return 1 }

  local tmp_fetch
  tmp_fetch=$(mktemp) || { log_err "Failed to create temp file"; return 1 }

  local entry label url fetched=0
  for entry in "${_ADBLOCK_HOSTS_MIRRORS[@]}"; do
    label="${entry%%|*}"
    url="${entry#*|}"
    log "Trying mirror: $label"
    if curl -fsSL --connect-timeout 5 --max-time 15 "$url" -o "$tmp_fetch" && [[ -s "$tmp_fetch" ]]; then
      log_ok "Fetched from $label"
      fetched=1
      break
    fi
    log_warn "Mirror failed: $label"
  done

  if (( ! fetched )); then
    log_err "All mirrors failed, /etc/hosts left untouched"
    rm -f "$tmp_fetch"
    return 1
  fi

  local begin_count end_count
  begin_count=$(grep -Fxc "$_ADBLOCK_HOSTS_BEGIN" /etc/hosts)
  end_count=$(grep -Fxc "$_ADBLOCK_HOSTS_END" /etc/hosts)

  local tmp_out
  tmp_out=$(mktemp) || { log_err "Failed to create temp file"; rm -f "$tmp_fetch"; return 1 }

  if (( begin_count == 0 && end_count == 0 )); then
    log "No managed block found, appending one to the end of /etc/hosts"
    {
      cat /etc/hosts
      echo
      print -r -- "$_ADBLOCK_HOSTS_BEGIN"
      cat "$tmp_fetch"
      print -r -- "$_ADBLOCK_HOSTS_END"
    } > "$tmp_out"
  elif (( begin_count == 1 && end_count == 1 )); then
    local begin_line end_line
    begin_line=$(grep -Fxn "$_ADBLOCK_HOSTS_BEGIN" /etc/hosts | cut -d: -f1)
    end_line=$(grep -Fxn "$_ADBLOCK_HOSTS_END" /etc/hosts | cut -d: -f1)

    if (( begin_line >= end_line )); then
      log_err "Managed block markers are out of order in /etc/hosts, fix manually before retrying"
      rm -f "$tmp_fetch" "$tmp_out"
      return 1
    fi

    log "Replacing existing managed block (lines $begin_line-$end_line)"
    {
      (( begin_line > 1 )) && sed -n "1,$((begin_line - 1))p" /etc/hosts
      print -r -- "$_ADBLOCK_HOSTS_BEGIN"
      cat "$tmp_fetch"
      print -r -- "$_ADBLOCK_HOSTS_END"
      sed -n "$((end_line + 1)),\$p" /etc/hosts
    } > "$tmp_out"
  else
    log_err "Managed block markers are corrupted in /etc/hosts (expected exactly one BEGIN and one END), fix manually before retrying"
    rm -f "$tmp_fetch" "$tmp_out"
    return 1
  fi

  rm -f "$tmp_fetch"

  local backup="/etc/hosts.bak.$(date +%Y%m%d%H%M%S)"
  if sudo cp /etc/hosts "$backup"; then
    log_dim "Backed up original hosts to $backup"
  else
    log_err "Failed to back up original hosts, aborting"
    rm -f "$tmp_out"
    return 1
  fi

  if sudo cp "$tmp_out" /etc/hosts; then
    log_ok "hosts updated ($(wc -l < /etc/hosts | tr -d ' ') lines total)"
  else
    log_err "Failed to write /etc/hosts, restore from $backup if needed"
    rm -f "$tmp_out"
    return 1
  fi

  rm -f "$tmp_out"
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
