#!/usr/bin/env bash

_run_with_executor() {
  # 通过可选执行器运行命令：
  #   - 未提供执行器：当前 shell 用 bash -lc 执行
  #   - 提供执行器函数名：调用该函数执行命令字符串
  local cmd="$1"
  local executor="${2:-}"
  if [ -n "$executor" ]; then
    "$executor" "$cmd"
  else
    bash -lc "$cmd"
  fi
}

detect_downloader() {
  # 下载器优先级：aria2c > wget > curl
  if command -v aria2c >/dev/null 2>&1; then
    echo aria2c
  elif command -v wget >/dev/null 2>&1; then
    echo wget
  elif command -v curl >/dev/null 2>&1; then
    echo curl
  else
    echo ''
  fi
}

ensure_downloader() {
  # 确保至少存在一个下载器；都没有时优先提示并尝试安装 aria2
  local downloader
  downloader="$(detect_downloader)"
  if [ -n "$downloader" ]; then
    echo "$downloader"
    return 0
  fi

  log_warn 'No aria2c/wget/curl; installing aria2 as downloader'
  ensure_cmd_installed aria2 1
  echo aria2c
}

download_to_file() {
  # 下载 URL 到目标文件（已存在则跳过，传 $4=1 强制覆盖）
  # 参数：
  #   $1：URL
  #   $2：目标路径
  #   $3：可选执行器函数名
  #   $4：可选，强制覆盖（1=覆盖，默认 0=跳过）
  local url="$1"
  local destination="$2"
  local executor="${3:-}"
  local force="${4:-0}"

  if [ "$force" != '1' ] && [ -f "$destination" ]; then
    log "File exists; skip download: $destination"
    return 0
  fi
  local downloader
  local q_url
  local q_dst
  local q_dir
  local cmd

  downloader="$(ensure_downloader)"
  q_url="$(printf '%q' "$url")"
  q_dst="$(printf '%q' "$destination")"
  q_dir="$(printf '%q' "$(dirname "$destination")")"

  if [ "$downloader" = 'aria2c' ]; then
    cmd="mkdir -p $q_dir && aria2c -c -x 8 -s 8 -k 1M --summary-interval=0 --console-log-level=warn --dir $q_dir -o $(printf '%q' "$(basename "$destination")") $q_url"
  elif [ "$downloader" = 'wget' ]; then
    cmd="mkdir -p $q_dir && wget -q -O $q_dst $q_url"
  else
    cmd="mkdir -p $q_dir && curl -fsSL -o $q_dst $q_url"
  fi

  log "Download: $url -> $destination (via $downloader)"
  _run_with_executor "$cmd" "$executor"
}

run_remote_script() {
  # 使用 aria2c/wget/curl 拉取远程脚本并交给 sh 执行
  # 参数：
  #   $1：脚本 URL
  # 返回：
  #   0 — 执行成功
  #   1 — 脚本执行失败
  #   2 — 无可用下载器
  local url="$1"
  local downloader
  local tmp_file

  downloader="$(detect_downloader)"
  if [ "$downloader" = 'aria2c' ]; then
    tmp_file="$(mktemp)"
    log "Running: aria2c fetch + sh ($url)"
    if aria2c -c -x 8 -s 8 -k 1M --summary-interval=0 --console-log-level=warn \
      --dir "$(dirname "$tmp_file")" -o "$(basename "$tmp_file")" "$url"; then
      # 显式捕获并回传 sh 的退出码：否则函数会落到末尾 rm（返回 0），
      # 把「脚本执行失败」掩盖成成功，违反本函数 1=失败 的契约，且与 curl/wget 分支不一致
      local sh_rc=0
      sh "$tmp_file" || sh_rc=$?
      rm -f "$tmp_file"
      return "$sh_rc"
    else
      rm -f "$tmp_file"
      return 1
    fi
  elif [ "$downloader" = 'curl' ]; then
    log "Running: curl -sS $url | sh"
    curl -sS "$url" | sh
  elif [ "$downloader" = 'wget' ]; then
    log "Running: wget -qO- $url | sh"
    wget -qO- "$url" | sh
  else
    log_warn 'No aria2c/wget/curl; cannot run remote script'
    return 2
  fi
}
