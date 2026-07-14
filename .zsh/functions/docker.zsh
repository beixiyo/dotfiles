# Docker: zsh as shell glue (fzf / execute), bun as core (list, Docker Hub API)

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

_docker_start_mac() {
  [[ -d /Applications/Docker.app ]] || return 1
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

  if is_mac; then
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

dinfo() {
  require bun || return 1
  bun run "$DOCKER_BUN_SCRIPT" dinfo "$@"
}

dd() {
  _docker_ensure_ready || return 1
  DOCKER_USE_SUDO="$_DOCKER_USE_SUDO" bun run "$_DD_BUN/dd-cmd.ts" "$@"
}

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
