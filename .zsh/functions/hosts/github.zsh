# GitHub hosts tools

# GitHub520 的独立发布地址优先，不依赖 GitHub 域名自身可用
_GITHUB_HOSTS_MIRRORS=(
  'HelloGitHub|https://raw.hellogithub.com/hosts'
  'GitHub Raw|https://raw.githubusercontent.com/521xueweihan/GitHub520/main/hosts'
)

_GITHUB_SOURCE_BEGIN='# GitHub520 Host Start'
_GITHUB_SOURCE_END='# GitHub520 Host End'
_GITHUB_HOSTS_BEGIN='# >>> refreshGithubHosts BEGIN (managed, do not edit inside) >>>'
_GITHUB_HOSTS_END='# <<< refreshGithubHosts END <<<'

# 拉取 GitHub520 hosts 并更新其托管区块
# Usage: refreshGithubHosts
refreshGithubHosts() {
  require curl || return 1

  log_warn "This will update the refreshGithubHosts-managed block in /etc/hosts; everything outside the markers is left untouched"
  confirm "Proceed?" || { log "Cancelled"; return 1 }

  local tmp_fetch tmp_body
  tmp_fetch=$(mktemp) || { log_err "Failed to create temp file"; return 1 }
  tmp_body=$(mktemp) || {
    log_err "Failed to create temp file"
    rm -f "$tmp_fetch"
    return 1
  }

  local entry label url fetched=0
  for entry in "${_GITHUB_HOSTS_MIRRORS[@]}"; do
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
    rm -f "$tmp_fetch" "$tmp_body"
    return 1
  fi

  local begin_count end_count begin_line end_line
  begin_count=$(grep -Fxc "$_GITHUB_SOURCE_BEGIN" "$tmp_fetch")
  end_count=$(grep -Fxc "$_GITHUB_SOURCE_END" "$tmp_fetch")

  if (( begin_count != 1 || end_count != 1 )); then
    log_err "Fetched GitHub hosts has invalid markers, /etc/hosts left untouched"
    rm -f "$tmp_fetch" "$tmp_body"
    return 1
  fi

  begin_line=$(grep -Fxn "$_GITHUB_SOURCE_BEGIN" "$tmp_fetch" | cut -d: -f1)
  end_line=$(grep -Fxn "$_GITHUB_SOURCE_END" "$tmp_fetch" | cut -d: -f1)
  if (( begin_line >= end_line )); then
    log_err "Fetched GitHub hosts markers are out of order, /etc/hosts left untouched"
    rm -f "$tmp_fetch" "$tmp_body"
    return 1
  fi

  sed -n "$((begin_line + 1)),$((end_line - 1))p" "$tmp_fetch" > "$tmp_body"
  if [[ ! -s "$tmp_body" ]]; then
    log_err "Fetched GitHub hosts block is empty, /etc/hosts left untouched"
    rm -f "$tmp_fetch" "$tmp_body"
    return 1
  fi

  _hosts_replace_managed_block \
    'refreshGithubHosts' \
    "$_GITHUB_HOSTS_BEGIN" \
    "$_GITHUB_HOSTS_END" \
    "$tmp_body" \
    "$_GITHUB_SOURCE_BEGIN" \
    "$_GITHUB_SOURCE_END"

  local rc=$?
  rm -f "$tmp_fetch" "$tmp_body"
  return "$rc"
}
