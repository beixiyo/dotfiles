# Download file: aria2c > wget > curl
# Usage: download [--no-proxy] <url> [filepath]

# Probe remote file: outputs "<size_bytes>\t<ranges:0|1>"; returns 1 on failure
_download_probe() {
  local url=$1 proxy=$2
  local -a proxy_args
  local -a no_proxy_env=(HTTP_PROXY= HTTPS_PROXY= http_proxy= https_proxy= ALL_PROXY= all_proxy=)
  if [[ -n "$proxy" ]]; then
    proxy_args=(-x "$proxy")
    no_proxy_env=()
  else
    proxy_args=(--noproxy '*')
  fi

  local headers
  headers=$(env "${no_proxy_env[@]}" curl -sILf --max-time 5 "${proxy_args[@]}" "$url" 2>/dev/null) \
    || headers=$(env "${no_proxy_env[@]}" curl -sf --max-time 5 -r 0-0 -D - -o /dev/null "${proxy_args[@]}" "$url" 2>/dev/null) \
    || return 1

  local size ranges
  size=$(print -r -- "$headers" | awk 'BEGIN{IGNORECASE=1} /^content-length:/{v=$2} END{gsub(/\r/,"",v); print v+0}')
  ranges=$(print -r -- "$headers" | awk 'BEGIN{IGNORECASE=1; r=0} /^accept-ranges:[ \t]*bytes/{r=1} /^content-range:/{r=1} END{print r}')
  print -r -- "${size:-0}"$'\t'"${ranges:-0}"
}

# Choose aria2 preallocation based on target filesystem type
_download_fs_alloc() {
  local fstype
  fstype=$(stat -f -c %T "$1" 2>/dev/null)
  case "$fstype" in
    ext2/ext3|ext4|xfs|btrfs|f2fs) print -r -- falloc ;;
    *) print -r -- prealloc ;;
  esac
}

download() {
  local use_proxy=1
  local url
  local filepath
  local proxy_url=''

  if [[ "$1" == '--no-proxy' ]]; then
    use_proxy=0
    shift
  fi

  url="$1"
  filepath="$2"

  if [[ -z "$url" ]]; then
    echo "Usage: download [--no-proxy] <url> [filepath]"
    return 1
  fi

  local out_dir out_file downloads_dir=''
  if [[ -n "$XDG_DOWNLOAD_DIR" && -d "$XDG_DOWNLOAD_DIR" ]]; then
    downloads_dir="$XDG_DOWNLOAD_DIR"
  elif has xdg-user-dir; then
    downloads_dir="$(xdg-user-dir DOWNLOAD 2>/dev/null)"
    [[ "$downloads_dir" == "$HOME" ]] && downloads_dir=''
  fi
  [[ -z "$downloads_dir" && -d "$HOME/Downloads" ]] && downloads_dir="$HOME/Downloads"

  if [[ -z "$filepath" ]]; then
    out_dir="$PWD"
    if [[ -n "$downloads_dir" && "$PWD" != "$downloads_dir" ]] && has fzf; then
      local choice
      choice="$(printf '%s\n%s\n' "$downloads_dir" "$PWD" | fzf \
        --height=~40% \
        --prompt='Save to > ' \
        --header='Select download directory' \
        --no-info \
        --reverse \
        --ansi)" || return 130
      [[ -n "$choice" ]] && out_dir="$choice"
    fi
    out_file="${${url%%\?*}##*/}"
    out_file="${out_file%%#*}"
  elif [[ -d "$filepath" || "$filepath" == */ ]]; then
    out_dir="${filepath%/}"
    [[ -z "$out_dir" ]] && out_dir="/"
    out_file="${${url%%\?*}##*/}"
    out_file="${out_file%%#*}"
  else
    out_dir="${filepath:h}"
    out_file="${filepath:t}"
    [[ "$out_dir" == "$filepath" ]] && out_dir="."
  fi

  if [[ -z "$out_file" ]]; then
    log_err "cannot parse filename from URL, specify filepath explicitly"
    return 1
  fi

  filepath="$out_dir/$out_file"
  mkdir -p "$out_dir" || return 1

  if (( use_proxy )); then
    proxy_url="${https_proxy:-${HTTPS_PROXY:-${http_proxy:-${HTTP_PROXY:-${all_proxy:-${ALL_PROXY:-}}}}}}"
  fi

  if has aria2c; then
    # 按文件大小与是否支持 Range 选档：小文件不分段，大文件用更大 -k 与磁盘缓存
    local -i size=0 ranges=0
    local probe
    if probe=$(_download_probe "$url" "$proxy_url" 2>/dev/null); then
      size=${probe%%$'\t'*}
      ranges=${probe##*$'\t'}
    fi

    local -i MB=$((1024 * 1024))
    local -i x=8 split_mb=1 cache_mb=16
    if (( ranges == 0 && size > 0 )); then
      x=1
    elif (( size <= 0 )); then
      : # 未知大小，保守默认 x=8
    elif (( size < 10 * MB )); then
      x=4
    elif (( size < 100 * MB )); then
      x=8; cache_mb=32
    elif (( size < 1024 * MB )); then
      x=16; split_mb=2; cache_mb=64
    else
      x=16; split_mb=4; cache_mb=128
    fi

    local alloc
    alloc=$(_download_fs_alloc "$out_dir")

    if (( size > 0 )); then
      local size_h
      size_h=$(numfmt --to=iec --suffix=B "$size" 2>/dev/null || print -r -- "${size}B")
      echo "📦 $size_h | -x $x -k ${split_mb}M --disk-cache=${cache_mb}M --file-allocation=$alloc"
    fi

    local -a aria2_args=(
      -c
      -x "$x" -s "$x"
      -k "${split_mb}M"
      --min-split-size=1M
      --file-allocation="$alloc"
      --disk-cache="${cache_mb}M"
      --optimize-concurrent-downloads=true
      --summary-interval=0
      --console-log-level=warn
      --dir "$out_dir"
      -o "$out_file"
    )

    if [[ -n "$proxy_url" ]]; then
      aria2c "${aria2_args[@]}" --all-proxy="$proxy_url" "$url"
    else
      HTTP_PROXY= HTTPS_PROXY= http_proxy= https_proxy= ALL_PROXY= all_proxy= \
        aria2c "${aria2_args[@]}" "$url"
    fi
    return $?
  fi

  if has wget; then
    if [[ -n "$proxy_url" ]]; then
      HTTP_PROXY="$proxy_url" HTTPS_PROXY="$proxy_url" http_proxy="$proxy_url" https_proxy="$proxy_url" \
        wget -c -O "$filepath" "$url"
    else
      wget --no-proxy -c -O "$filepath" "$url"
    fi
    return $?
  fi

  if has curl; then
    if [[ -n "$proxy_url" ]]; then
      curl -fL -C - -x "$proxy_url" --output "$filepath" "$url"
    else
      HTTP_PROXY= HTTPS_PROXY= http_proxy= https_proxy= ALL_PROXY= all_proxy= \
        curl -fL -C - --noproxy '*' --output "$filepath" "$url"
    fi
    return $?
  fi

  log_err "no download tool found, install aria2 / wget / curl"
  return 1
}
