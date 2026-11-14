# Docker：zsh 负责 shell 胶水（fzf / 执行），bun 负责核心逻辑（列表、Docker Hub API）

() {
  local dir="${${(%):-%x}:A:h}"
  DOCKER_BUN_SCRIPT="$dir/bun/src/docker.ts"
  _DD_BUN="$dir/bun/src"
}

_DOCKER_USE_SUDO=0

_docker_endpoint() {
  local host="${DOCKER_HOST:-}"
  if [[ -z "$host" ]]; then
    host="$(command docker context inspect --format '{{ (index .Endpoints "docker").Host }}' 2>/dev/null | head -n 1)"
  fi

  print -r -- "$host"
}

_docker_desktop_socket() {
  local host="$(_docker_endpoint)"

  [[ "$host" == unix://* ]] && print -r -- "${host#unix://}"
}

_docker_has_cli() {
  (( $+commands[docker] ))
}

_docker_can_use_sudo() {
  [[ "$(_docker_endpoint)" == unix:///var/run/docker.sock ]]
}

# 当前 endpoint 是否为 Kiri：macOS 为 ~/.kiri*/run/docker.sock，Linux 为 /run/kiri/docker.sock
_docker_is_kiri() {
  local endpoint="$(_docker_endpoint)"

  case "$endpoint" in
    "unix://$HOME/.kiri/run/docker.sock"|"unix://$HOME/.kiri-dev/run/docker.sock"|unix:///run/kiri/docker.sock)
      return 0
      ;;
  esac

  return 1
}

# 定位 kiri 可执行文件
# Dev 版与正式版是同一个二进制，靠所在 bundle 区分 flavor，所以 Dev endpoint 只能用 Dev 自己的 kiri，
# 用 PATH 里的正式版会起错 daemon（服务 ~/.kiri 而不是 ~/.kiri-dev）
_docker_kiri_bin() {
  local -a candidates
  local bin

  if [[ "$(_docker_endpoint)" == "unix://$HOME/.kiri-dev/run/docker.sock" ]]; then
    candidates=("$HOME/.kiri-dev/bin/kiri" '/Applications/Kiri Dev.app/Contents/MacOS/kiri')
  else
    candidates=(${commands[kiri]} "$HOME/.kiri/bin/kiri" /Applications/Kiri.app/Contents/MacOS/kiri)
  fi

  for bin in "${candidates[@]}"; do
    [[ -x "$bin" ]] && { print -r -- "$bin"; return 0; }
  done

  return 1
}

_docker_can_start_mac() {
  local endpoint="$(_docker_endpoint)"

  [[ -z "$endpoint" ]] && return 0
  [[ "$endpoint" == "unix://$HOME/.docker/run/docker.sock" ]] && return 0
  [[ "$endpoint" == unix:///var/run/docker.sock ]] && return 0

  return 1
}

_docker_set_cli() {
  _DOCKER_USE_SUDO="$1"
}

_docker_sudo() {
  if is_tty; then
    sudo "$@"
  else
    sudo -n "$@"
  fi
}

_docker_run() {
  if [[ "$_DOCKER_USE_SUDO" == 1 ]]; then
    _docker_sudo docker "$@"
  else
    command docker "$@"
  fi
}

_docker_should_skip_ready() {
  local arg skip_value=0

  (( $# == 0 )) && return 0

  for arg in "$@"; do
    if (( skip_value )); then
      skip_value=0
      continue
    fi

    case "$arg" in
      --context|--host|-c|-H|--context=*|--host=*|-c?*|-H?*)
        return 0
        ;;
      --config|--log-level|--tlscacert|--tlscert|--tlskey)
        skip_value=1
        ;;
      -v|--version|--help)
        return 0
        ;;
      --)
        continue
        ;;
      -*)
        ;;
      help|context|login|logout)
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  done

  return 0
}

_docker_select_ready_cli() {
  if command docker info >/dev/null 2>&1; then
    _docker_set_cli 0
    return 0
  fi

  if ! is_mac && _docker_can_use_sudo && has sudo && sudo -n docker info >/dev/null 2>&1; then
    _docker_set_cli 1
    return 0
  fi

  return 1
}

_docker_wait_ready() {
  local waited=0
  local max_wait="${DOCKER_DAEMON_WAIT_SECONDS:-90}"

  while (( waited < max_wait )); do
    _docker_select_ready_cli && return 0

    sleep 1
    (( waited++ ))
  done

  return 1
}

# Kiri 引擎启动：系统级 socket（Linux）是 systemd 服务，需要 sudo；用户级 socket（macOS）后台起 daemon（无 GUI）
_docker_start_kiri() {
  local socket="$(_docker_desktop_socket)"

  if [[ "$socket" == /run/kiri/docker.sock ]]; then
    # 服务已在跑但当前用户连不上：再启动也没用，直接提示授权
    if [[ -S "$socket" && ! -w "$socket" ]]; then
      log_err "Kiri engine is running but $socket is not accessible. Grant access: sudo kiri host-access $USER"
      return 1
    fi

    if has systemctl && [[ -d /run/systemd/system ]] && has sudo; then
      log_warn 'Kiri engine is not ready, starting kiri service...'
      _docker_sudo systemctl start kiri 2>/dev/null && return 0
    fi

    log_err 'Kiri engine is not ready. Start it manually: sudo systemctl start kiri'
    return 1
  fi

  is_mac || {
    log_err "Kiri engine is not ready for endpoint: $(_docker_endpoint). Start it manually: kiri daemon"
    return 1
  }

  local bin
  bin="$(_docker_kiri_bin)" || {
    log_err 'Kiri endpoint is selected but the kiri binary was not found'
    return 1
  }

  log_warn 'Kiri engine is not ready, starting kiri daemon...'
  nohup "$bin" daemon </dev/null >/dev/null 2>&1 &!
}

_docker_start_mac() {
  [[ -d /Applications/Docker.app ]] || {
    log_err "Docker daemon is not ready for endpoint: $(_docker_endpoint) (Docker.app is not installed, start the engine manually)"
    return 1
  }
  _docker_can_start_mac || {
    log_err "Docker daemon is not ready for endpoint: $(_docker_endpoint)"
    return 1
  }

  log_warn 'Docker daemon is not ready, starting Docker Desktop...'
  /usr/bin/open -gj -b com.docker.docker 2>/dev/null || /usr/bin/open -gj /Applications/Docker.app
}

_docker_start_linux() {
  if is_wsl; then
    log_err 'Docker daemon is not ready. Start Docker Desktop on Windows and enable WSL integration.'
    return 1
  fi

  has sudo || {
    log_err 'Docker daemon is not ready and sudo is unavailable'
    return 1
  }

  _docker_can_use_sudo || {
    log_err "Docker daemon is not ready for endpoint: $(_docker_endpoint)"
    return 1
  }

  if is_tty; then
    sudo -v || return 1
  else
    sudo -n true 2>/dev/null || {
      log_err 'Docker daemon is not ready and sudo requires an interactive terminal'
      return 1
    }
  fi

  _docker_sudo docker info >/dev/null 2>&1 && {
    _docker_set_cli 1
    return 0
  }

  log_warn 'Docker daemon is not ready, starting Docker service...'
  if has systemctl && [[ -d /run/systemd/system ]]; then
    _docker_sudo systemctl start docker 2>/dev/null && return 0
  fi

  if has service && [[ -x /etc/init.d/docker ]]; then
    _docker_sudo service docker start 2>/dev/null && return 0
  fi

  if [[ -x /etc/init.d/docker ]]; then
    _docker_sudo /etc/init.d/docker start 2>/dev/null && return 0
  fi

  log_err 'Could not start Docker service automatically'
  return 1
}

_docker_ensure_ready() {
  _docker_has_cli || {
    log_err 'docker CLI is not installed or not available in PATH'
    return 1
  }

  _docker_select_ready_cli && return 0

  if _docker_is_kiri; then
    _docker_start_kiri || return 1
  elif is_mac; then
    _docker_start_mac || return 1
  else
    _docker_start_linux || return 1
  fi

  _docker_wait_ready && {
    log_ok 'Docker daemon is ready'
    return 0
  }

  local socket="$(_docker_desktop_socket)"
  if [[ -n "$socket" && ! -S "$socket" ]]; then
    log_err "Docker daemon is not ready: $socket does not exist"
  else
    log_err 'Docker daemon is not ready'
  fi

  return 1
}

# docker 命令包装：执行前确保引擎就绪（必要时自动拉起 Kiri / Docker Desktop / Docker 服务），再转发全部参数
docker() {
  if _docker_should_skip_ready "$@"; then
    _docker_has_cli || {
      log_err 'docker CLI is not installed or not available in PATH'
      return 1
    }

    command docker "$@"
    return
  fi

  _docker_ensure_ready || return 1
  _docker_run "$@"
}

# 查询 Docker Hub 镜像信息：dinfo <repo> <tag> [arch] [os]
dinfo() {
  require bun || return 1
  bun run "$DOCKER_BUN_SCRIPT" dinfo "$@"
}

# 容器与镜像的 fzf 面板：日志、exec、复制 ID、停止、运行、重启、删除，支持多选
dd() {
  _docker_ensure_ready || return 1
  DOCKER_USE_SUDO="$_DOCKER_USE_SUDO" bun run "$_DD_BUN/dd-cmd.ts" "$@"
}

# fzf 选择一个运行中的容器并进入 shell（优先 bash，回退 sh）
dex() {
  require docker || return 1
  require fzf || return 1
  require bun || return 1
  _docker_ensure_ready || return 1
  local line id gen_list
  gen_list="DOCKER_USE_SUDO=$_DOCKER_USE_SUDO bun run \"$DOCKER_BUN_SCRIPT\" list containers 2>/dev/null"
  line=$(eval "$gen_list" < /dev/null | fzf --header "Select container to exec into" --header-lines 0)
  [[ -z "$line" ]] && return
  id=$(echo "$line" | cut -f1)
  _docker_run exec -it "$id" bash 2>/dev/null || _docker_run exec -it "$id" sh
}

# fzf 选择容器（含已退出）并持续跟踪日志
dlogs() {
  require docker || return 1
  require fzf || return 1
  require bun || return 1
  _docker_ensure_ready || return 1
  local line id gen_list
  gen_list="DOCKER_USE_SUDO=$_DOCKER_USE_SUDO bun run \"$DOCKER_BUN_SCRIPT\" list containers --all 2>/dev/null"
  line=$(eval "$gen_list" < /dev/null | fzf --header "Select container for logs -f" --header-lines 0)
  [[ -z "$line" ]] && return
  id=$(echo "$line" | cut -f1)
  _docker_run logs -f "$id"
}

# 跟踪指定容器的日志，默认只看本次启动之后的，加 --no-since 看全部：dlog <container-name> [--no-since]
dlog() {
  require docker || return 1
  _docker_ensure_ready || return 1
  local no_since name
  for arg in "$@"; do
    [[ "$arg" == --no-since ]] && no_since=1
    [[ "$arg" != --no-since ]] && name="$arg"
  done
  name="${name:?Usage: dlog <container-name> [--no-since]}"
  if (( no_since )); then
    _docker_run logs -f "$name"
  else
    _docker_run logs -f "$name" --since "$(_docker_run inspect "$name" --format='{{.State.StartedAt}}')"
  fi
}

# fzf 选择容器并复制其 ID（有 clip.exe 时写入剪贴板，否则直接输出）
dcp() {
  require docker || return 1
  require fzf || return 1
  require bun || return 1
  _docker_ensure_ready || return 1
  local line id gen_list
  gen_list="DOCKER_USE_SUDO=$_DOCKER_USE_SUDO bun run \"$DOCKER_BUN_SCRIPT\" list containers --all 2>/dev/null"
  line=$(eval "$gen_list" < /dev/null | fzf --header "Select container (copy ID)" --header-lines 0)
  [[ -z "$line" ]] && return
  id=$(echo "$line" | cut -f1)
  if has clip.exe; then
    printf '%s' "$id" | clip.exe
    echo "Copied: $id"
  else
    echo "$id"
  fi
}

# 创建一组 dtest-* 测试容器，用来试 dd / dex / dlogs / dcp
dtest() {
  require docker || return 1
  _docker_ensure_ready || return 1
  echo "Creating hello-world level test containers..."
  _docker_run run --name dtest-hw1 hello-world
  _docker_run run --name dtest-hw2 hello-world
  _docker_run run --name dtest-hw3 hello-world
  _docker_run run -d --name dtest-run busybox:latest sleep infinity
  echo "Started: dtest-hw1, dtest-hw2, dtest-hw3 (exited), dtest-run (running)"
  echo "Try: dd (panel, add --all for exited) | dex/dlogs/dcp on dtest-run"
}

# 删除所有 dtest-* 测试容器
dclean-test() {
  require docker || return 1
  _docker_ensure_ready || return 1
  local ids
  ids=$(_docker_run ps -aq -f name=^dtest- 2>/dev/null)
  if [[ -z "$ids" ]]; then
    echo "No dtest-* containers found."
    return 0
  fi
  echo "Stopping and removing: $(echo $ids | tr '\n' ' ')"
  _docker_run rm -f $ids
  echo "Done."
}
