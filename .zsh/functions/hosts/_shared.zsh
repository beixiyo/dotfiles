# Shared helpers for managed /etc/hosts blocks

# Replace one marked block in /etc/hosts with a prepared body file
# Optional legacy markers are migrated in place when the current markers are absent
_hosts_replace_managed_block() {
  local name=$1 begin=$2 end=$3 body_file=$4
  local legacy_begin=$5 legacy_end=$6
  local begin_count end_count legacy_begin_count legacy_end_count
  local active_begin active_end mode

  begin_count=$(grep -Fxc "$begin" /etc/hosts)
  end_count=$(grep -Fxc "$end" /etc/hosts)

  if (( begin_count == 1 && end_count == 1 )); then
    active_begin=$begin
    active_end=$end
    mode='replace'
  elif (( begin_count == 0 && end_count == 0 )); then
    if [[ -z "$legacy_begin" && -z "$legacy_end" ]]; then
      mode='append'
    else
      legacy_begin_count=$(grep -Fxc "$legacy_begin" /etc/hosts)
      legacy_end_count=$(grep -Fxc "$legacy_end" /etc/hosts)

      if (( legacy_begin_count == 1 && legacy_end_count == 1 )); then
        active_begin=$legacy_begin
        active_end=$legacy_end
        mode='migrate'
      elif (( legacy_begin_count == 0 && legacy_end_count == 0 )); then
        mode='append'
      else
        log_err "Legacy $name-managed block markers are corrupted in /etc/hosts, fix manually before retrying"
        return 1
      fi
    fi
  else
    log_err "Managed block markers are corrupted in /etc/hosts (expected exactly one BEGIN and one END), fix manually before retrying"
    return 1
  fi

  local tmp_out
  tmp_out=$(mktemp) || { log_err "Failed to create temp file"; return 1 }

  if [[ "$mode" == 'append' ]]; then
    log "No $name-managed block found, appending one to the end of /etc/hosts"
    {
      cat /etc/hosts
      echo
      print -r -- "$begin"
      cat "$body_file"
      print -r -- "$end"
    } > "$tmp_out"
  else
    local begin_line end_line
    begin_line=$(grep -Fxn "$active_begin" /etc/hosts | cut -d: -f1)
    end_line=$(grep -Fxn "$active_end" /etc/hosts | cut -d: -f1)

    if (( begin_line >= end_line )); then
      log_err "Managed block markers are out of order in /etc/hosts, fix manually before retrying"
      rm -f "$tmp_out"
      return 1
    fi

    if [[ "$mode" == 'migrate' ]]; then
      log "Migrating existing $name-managed block (lines $begin_line-$end_line)"
    else
      log "Replacing existing $name-managed block (lines $begin_line-$end_line)"
    fi

    {
      (( begin_line > 1 )) && sed -n "1,$((begin_line - 1))p" /etc/hosts
      print -r -- "$begin"
      cat "$body_file"
      print -r -- "$end"
      sed -n "$((end_line + 1)),\$p" /etc/hosts
    } > "$tmp_out"
  fi

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
