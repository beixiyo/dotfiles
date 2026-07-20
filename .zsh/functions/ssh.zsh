#!/usr/bin/env zsh

# 从 ~/.ssh/config 读取主机，并通过 fzf 快速连接
# 用法：cssh [初始查询]

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

# 远端脚本开头：把位置参数 $1 解析为 path，保留 ~ 与 ~/ 的 HOME 语义
_CSCP_REMOTE_PRELUDE='case "$1" in "~") path="$HOME" ;; "~/"*) path="$HOME/${1#??}" ;; *) path="$1" ;; esac
'

_cscp_remote_cmd() {
  # 远端登录 Shell 未必是 POSIX Shell（如 fish），命令统一交给 sh 执行
  # 路径以位置参数传入而非拼进脚本，只需一层引号，避免跨 Shell 的转义差异
  local remote_path="$2"
  local script="${_CSCP_REMOTE_PRELUDE}$1"
  print -r -- "sh -c ${(qq)script} cscp ${(qq)remote_path}"
}

# 交互式上传或下载文件；目录使用 tar 流式传输，普通文件使用 scp
# 用法：cscp [本地基准目录]
cscp() {
  require fzf || return 1

  local base_dir="${1:-.}"
  if [[ ! -d "$base_dir" ]]; then
    log_err "directory not found: $base_dir"
    return 1
  fi

  local action
  action=$(printf "^ Upload (Local -> Remote)\nv Download (Remote -> Local)" \
    | fzf --prompt="SCP Action > " --height=~30% --reverse) || return 0

  local ssh_config="${HOME}/.ssh/config"
  [[ -f "$ssh_config" ]] || touch "$ssh_config"

  if [[ "$action" == *"Upload"* ]]; then
    # 从基准目录选择一个或多个待上传文件、目录
    local local_path_str
    if has fd; then
      local_path_str=$(fd --hidden --no-ignore-parent --exclude .git . "$base_dir" \
        | fzf -m --prompt="Local files/dirs (Tab select) > " --height=~50% --reverse) || return 0
    else
      local_path_str=$(find "$base_dir" -maxdepth 4 2>/dev/null \
        | fzf -m --prompt="Local files/dirs (Tab select) > " --height=~50% --reverse) || return 0
    fi
    local local_paths=("${(@f)local_path_str}")

    local host
    host=$(awk '/^Host / && !/\*/ { for (i=2; i<=NF; i++) print $i }' "$ssh_config" \
      | fzf --prompt="Select Host > " --height=~50% --reverse) || return 0

    local remote_path=""
    vared -p "Remote destination directory > " remote_path || return 0
    [[ -z "$remote_path" ]] && return 0

    # 纯文件列表直接交给 scp；包含任意目录时切换到 tar 管道
    local use_tar=0
    local selected_path
    for selected_path in "${local_paths[@]}"; do
      if [[ -d "$selected_path" ]]; then
        use_tar=1
        break
      fi
    done

    if (( use_tar )); then
      # tar 在基准目录内按相对路径打包，避免把本机绝对路径带到远端
      local absolute_base="${base_dir:A}"
      local relative_path
      local relative_paths=()
      for selected_path in "${local_paths[@]}"; do
        relative_path="${selected_path:A}"
        if [[ "$relative_path" == "$absolute_base" ]]; then
          relative_path="."
        else
          relative_path="${relative_path#$absolute_base/}"
        fi
        relative_paths+=("$relative_path")
      done

      # 不传输 macOS 扩展属性，避免 GNU tar 警告未知的 LIBARCHIVE.xattr 字段
      log "tar ${relative_paths[*]} | ssh $host:$remote_path"
      tar --no-xattrs -cf - -C "$absolute_base" -- "${relative_paths[@]}" \
        | ssh "$host" "$(_cscp_remote_cmd 'mkdir -p -- "$path" && tar -xf - -C "$path"' "$remote_path")"

      # 同时检查本地 tar 和远端 ssh/tar，任一环节失败都返回非零状态
      local transfer_status=("${pipestatus[@]}")
      (( transfer_status[1] == 0 && transfer_status[2] == 0 )) || return 1
    else
      log "scp ${local_paths[*]} $host:$remote_path"
      scp "${local_paths[@]}" "$host:$remote_path"
    fi

  elif [[ "$action" == *"Download"* ]]; then
    # 下载路径由用户输入，远端主机仍从 SSH config 中选择
    local host
    host=$(awk '/^Host / && !/\*/ { for (i=2; i<=NF; i++) print $i }' "$ssh_config" \
      | fzf --prompt="Select Host > " --height=~50% --reverse) || return 0

    local remote_path=""
    vared -p "Remote file or directory > " remote_path || return 0
    [[ -z "$remote_path" ]] && return 0

    # 本地基准目录本身也应作为候选项，避免没有子目录时 fzf 列表为空
    local local_path
    if has fd; then
      local_path=$({ print -r -- "$base_dir"; fd --type d --hidden --no-ignore-parent --exclude .git . "$base_dir"; } \
        | fzf --prompt="Local Dest Dir > " --height=~50% --reverse) || return 0
    else
      local_path=$(find "$base_dir" -maxdepth 3 -type d 2>/dev/null \
        | fzf --prompt="Local Dest Dir > " --height=~50% --reverse) || return 0
    fi

    # 先在远端判断资源类型：目录走 tar 管道，普通文件继续使用 scp
    local remote_type
    remote_type=$(ssh "$host" "$(_cscp_remote_cmd 'if [ -d "$path" ]; then printf d; elif [ -f "$path" ]; then printf f; else printf missing; fi' "$remote_path")") || return 1

    case "$remote_type" in
      d)
        # 在远端从父目录打包 basename，使解包后保留所选目录名
        log "ssh $host:$remote_path | tar -C $local_path"
        ssh "$host" "$(_cscp_remote_cmd 'parent=${path%/*}; name=${path##*/}; [ "$parent" = "$path" ] && parent=.; tar -cf - -C "$parent" -- "$name"' "$remote_path")" \
          | tar -xf - -C "$local_path"

        # 同时检查远端 tar/ssh 和本地解包状态
        local transfer_status=("${pipestatus[@]}")
        (( transfer_status[1] == 0 && transfer_status[2] == 0 )) || return 1
        ;;
      f)
        log "scp $host:$remote_path $local_path"
        scp "$host:$remote_path" "$local_path"
        ;;
      *)
        log_err "remote path not found: $remote_path"
        return 1
        ;;
    esac
  fi
}
