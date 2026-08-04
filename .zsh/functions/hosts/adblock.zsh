# Adblock hosts tools

# AWAvenue-Ads-Rule 广告屏蔽 hosts 订阅镜像，按可靠性从高到低排列，逐个重试
_ADBLOCK_HOSTS_MIRRORS=(
  'jsDelivr|https://gcore.jsdelivr.net/gh/TG-Twilight/AWAvenue-Ads-Rule@main/Filters/AWAvenue-Ads-Rule-hosts.txt'
  'CFCDN proxy|https://github.boki.moe/https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/Filters/AWAvenue-Ads-Rule-hosts.txt'
  'ghproxy|https://ghfast.top/https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/Filters/AWAvenue-Ads-Rule-hosts.txt'
  'GitHub Raw|https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/Filters/AWAvenue-Ads-Rule-hosts.txt'
  'CXPLAY mirror|https://script.cx.ms/awavenue/AWAvenue-Ads-Rule/main/Filters/AWAvenue-Ads-Rule-hosts.txt'
  'wangfugui mirror|https://cdn.uura.cn/AWAvenue/AWAvenue-Ads-Rule-hosts.txt'
)

_ADBLOCK_HOSTS_BEGIN='# >>> adblockHosts BEGIN (managed, do not edit inside) >>>'
_ADBLOCK_HOSTS_END='# <<< adblockHosts END <<<'

# 拉取 AWAvenue-Ads-Rule 广告屏蔽 hosts 并更新其托管区块
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

  _hosts_replace_managed_block \
    'adblockHosts' \
    "$_ADBLOCK_HOSTS_BEGIN" \
    "$_ADBLOCK_HOSTS_END" \
    "$tmp_fetch"

  local rc=$?
  rm -f "$tmp_fetch"
  return "$rc"
}
