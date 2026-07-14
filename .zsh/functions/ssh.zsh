#!/usr/bin/env zsh

# SSH quick connect: fzf select from ~/.ssh/config hosts
# Usage: cssh [query]

cssh() {
  require fzf || return 1

  local ssh_config="${HOME}/.ssh/config"
  [[ -f "$ssh_config" ]] || touch "$ssh_config"

  local host
  host=$(awk '/^Host / && !/\*/ { for (i=2; i<=NF; i++) print $i }' "$ssh_config" \
    | fzf --prompt="SSH > " --query="${1:-}" --height=~50% --reverse \
      --bind="${_fzf_scroll_binds:-},ctrl-n:down,ctrl-p:up")

  [[ -z "$host" ]] && return 0

  if [[ "$TERM" == "xterm-kitty" ]]; then
    kitten ssh "$host"
  else
    ssh "$host"
  fi
}

# SCP interactive transfer
# Usage: cscp [path]
cscp() {
  require fzf || return 1

  local base_dir="${1:-.}"
  if [[ ! -d "$base_dir" ]]; then
    log_err "directory not found: $base_dir"
    return 1
  fi

  local action
  action=$(printf "^ Upload (Local -> Remote)\nv Download (Remote -> Local)" | fzf --prompt="SCP Action > " --height=~30% --reverse)
  [[ -z "$action" ]] && return 0

  local ssh_config="${HOME}/.ssh/config"
  [[ -f "$ssh_config" ]] || touch "$ssh_config"

  if [[ "$action" == *"Upload"* ]]; then
    local local_path_str
    if has fd; then
      local_path_str=$(fd --hidden --no-ignore-parent --exclude .git . "$base_dir" | fzf -m --prompt="Local files/dirs (Tab select) > " --height=~50% --reverse)
    else
      local_path_str=$(find "$base_dir" -maxdepth 4 2>/dev/null | fzf -m --prompt="Local files/dirs (Tab select) > " --height=~50% --reverse)
    fi
    [[ -z "$local_path_str" ]] && return 0
    local local_paths=("${(@f)local_path_str}")

    local fzf_host_out
    fzf_host_out=$(awk '/^Host / && !/\*/ { for (i=2; i<=NF; i++) print $i }' "$ssh_config" \
      | fzf --prompt="Select Host > " --print-query --height=~50% --reverse)
    [[ $? -eq 130 ]] && return 0
    local host=$(echo "$fzf_host_out" | tail -n 1)
    [[ -z "$host" ]] && return 0

    echo "Enter remote destination path:"
    local fzf_out ret
    fzf_out=$(fzf --prompt="Remote Dest Dir > " --print-query --height=~50% --reverse < /dev/null)
    ret=$?
    [[ $ret -eq 130 ]] && return 0

    local remote_path
    remote_path=$(echo "$fzf_out" | tail -n 1)
    [[ -z "$remote_path" ]] && return 0

    log "scp -r ${local_paths[*]} $host:$remote_path"
    scp -r "${local_paths[@]}" "$host:$remote_path"

  elif [[ "$action" == *"Download"* ]]; then
    local fzf_host_out
    fzf_host_out=$(awk '/^Host / && !/\*/ { for (i=2; i<=NF; i++) print $i }' "$ssh_config" \
      | fzf --prompt="Select Host > " --print-query --height=~50% --reverse)
    [[ $? -eq 130 ]] && return 0
    local host=$(echo "$fzf_host_out" | tail -n 1)
    [[ -z "$host" ]] && return 0

    echo "Enter remote file/directory path:"
    local fzf_out ret
    fzf_out=$(fzf --prompt="Remote File/Dir > " --print-query --height=~50% --reverse < /dev/null)
    ret=$?
    [[ $ret -eq 130 ]] && return 0

    local remote_paths_str
    remote_paths_str=$(echo "$fzf_out" | tail -n 1)
    [[ -z "$remote_paths_str" ]] && return 0
    local remote_paths=("${(@f)remote_paths_str}")

    local local_path
    if has fd; then
      local_path=$(fd --type d --hidden --no-ignore-parent --exclude .git . "$base_dir" | fzf --prompt="Local Dest Dir > " --height=~50% --reverse)
    else
      local_path=$(find "$base_dir" -maxdepth 3 -type d 2>/dev/null | fzf --prompt="Local Dest Dir > " --height=~50% --reverse)
    fi
    [[ -z "$local_path" ]] && return 0

    local scp_args=()
    for p in "${remote_paths[@]}"; do
      scp_args+=("$host:$p")
    done

    log "scp -r ${scp_args[*]} $local_path"
    scp -r "${scp_args[@]}" "$local_path"
  fi
}
