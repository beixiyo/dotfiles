#!/usr/bin/env zsh

# Neovide 只作为独立 GUI 入口使用：
# - 不连接共享 Nvim 后端，避免终端 TUI 和 GUI 的绘制状态不一致
# - 在 tmux 里优先取当前 pane 的真实目录
# - 传目录时把该目录作为 Neovide cwd，传文件时保留当前 cwd
# - 在 tmux 单 pane window 中启动时，临时关闭该 window，Neovide 退出后恢复 cwd window
# - 在 tmux 多 pane window 中启动时，把当前 pane 停放进隐藏 session（tab 不留 window），Neovide 退出后恢复原布局
# - 在 Kitty native 中启动时，优先保留右侧 AI window；关闭源 window，Neovide 退出后近似恢复 cwd window

_neovide_bin() {
  command -v neovide 2>/dev/null
}

_neovide_app_available() {
  is_mac \
    && (( $+commands[open] )) \
    && osascript -e 'id of app "Neovide"' &>/dev/null
}

_neovide_launch() {
  if _neovide_app_available; then
    command open -n -b com.neovide.neovide --args "$@"
    return
  fi

  local bin
  if bin="$(_neovide_bin)"; then
    "$bin" "$@"
    return
  fi

  log_err '未找到 neovide：请先安装 Neovide CLI，或在 macOS 安装 Neovide.app'
  return 1
}

_neovide_supports_arg() {
  local flag="$1"
  local bin

  bin="$(_neovide_bin)" || return 1
  "$bin" --help 2>/dev/null | command grep -Fq -- "$flag"
}

_nvd_quote_args() {
  local -a quoted
  quoted=("${(@q)@}")
  print -r -- "${(j: :)quoted}"
}

_nvd_tmux_value() {
  local format="$1"
  tmux display-message -p -t "$TMUX_PANE" "$format" 2>/dev/null
}

_nvd_capture_gui_env() {
  local name
  local value

  for name in \
    PATH \
    DISPLAY \
    WAYLAND_DISPLAY \
    XDG_RUNTIME_DIR \
    XDG_CONFIG_HOME \
    XDG_DATA_HOME \
    XDG_STATE_HOME \
    XDG_CACHE_HOME \
    DBUS_SESSION_BUS_ADDRESS \
    SSH_AUTH_SOCK \
    XAUTHORITY \
    LANG \
    LC_ALL \
    NVIM_APPNAME \
    NEOVIDE_FRAME \
    NEOVIDE_OPENGL \
    NEOVIDE_SRGB \
    NEOVIDE_VSYNC \
    NEOVIM_BIN \
    NVD_KITTY_LISTEN_ON \
    NVD_KITTY_ORIGIN_WINDOW \
    NVD_KITTY_TARGET_WINDOW \
    NVD_TMUX_ORIGIN_PANE \
    NVD_TMUX_ORIGIN_WINDOW
  do
    value="${(P)name}"
    [[ -n "$value" ]] && print -r -- "export $name=${(q)value}"
  done
}

_nvd_tmux_can_start_blocking_neovide() {
  [[ -n "$TMUX_PANE" ]] || return 1
  command -v tmux &>/dev/null || return 1

  if ! _neovide_app_available; then
    _neovide_bin &>/dev/null || return 1
    _neovide_supports_arg '--no-fork' || return 1
  fi
}

_nvd_tmux_can_replace_window() {
  _nvd_tmux_can_start_blocking_neovide || return 1

  local pane_count
  local window_count
  pane_count="$(_nvd_tmux_value '#{window_panes}')"
  window_count="$(_nvd_tmux_value '#{session_windows}')"

  [[ "$pane_count" == <-> && "$window_count" == <-> ]] || return 1
  (( pane_count == 1 && window_count > 1 ))
}

_nvd_tmux_can_replace_pane() {
  _nvd_tmux_can_start_blocking_neovide || return 1

  local pane_count
  pane_count="$(_nvd_tmux_value '#{window_panes}')"

  [[ "$pane_count" == <-> ]] || return 1
  (( pane_count > 1 ))
}

# 收纳被 nvd 临时藏起的 pane 的隐藏 session
# 停到「别的 session」而非当前 session 的新 window，
# 这样它不会出现在当前 session 的 status bar 上，tab 保持干净
_NVD_TMUX_PARK_SESSION='_nvd_park'

_nvd_tmux_ensure_park_session() {
  local park="$_NVD_TMUX_PARK_SESSION"

  tmux has-session -t "=$park" 2>/dev/null && return 0

  tmux new-session -d -s "$park" || return 1
  # 隐藏 session 始终处于 detached 状态，必须关掉 destroy-unattached 才能常驻复用
  tmux set-option -t "=$park" destroy-unattached off 2>/dev/null
}

_nvd_kitty_can_replace_window() {
  # 优先级：tmux 是主路径。只要当前 shell 在 tmux 里，就不启用 Kitty native 近似方案
  [[ -z "${TMUX:-}" ]] || return 1
  [[ -n "${KITTY_WINDOW_ID:-}" && -n "${KITTY_LISTEN_ON:-}" ]] || return 1
  command -v kitten &>/dev/null || return 1
  command -v bun &>/dev/null || return 1
  command -v zsh &>/dev/null || return 1
}

_nvd_make_blocking_neovide_script() {
  local cwd="$1"
  shift

  local bin
  local script
  local open_bin
  local use_macos_app
  local line
  local -a on_exit_lines
  local -a neovide_args
  local -a neovide_cmd
  local -a neovim_args

  while (( $# > 0 )) && [[ "$1" != '--' ]]; do
    on_exit_lines+=("$1")
    shift
  done

  [[ "$1" == '--' ]] || return 1
  shift

  script="$(mktemp "${TMPDIR:-/tmp}/nvd.XXXXXX")" || return 1
  use_macos_app=false

  if _neovide_app_available; then
    open_bin="$(command -v open)" || return 1
    use_macos_app=true
  else
    bin="$(_neovide_bin)" || return 1
    neovide_args=(--no-fork)
  fi

  # macOS 上 Neovide 默认不用 sRGB，和 kitty / alacritty 等终端的观感可能不一致；
  # 只在 macOS 启用，避免影响 Linux/Wayland 下已经正常的颜色路径
  if is_mac && _neovide_supports_arg '--srgb'; then
    neovide_args+=(--srgb)
  fi

  neovide_args+=(--chdir "$cwd" "$@")

  if [[ -n "${NVD_TMUX_ORIGIN_PANE:-}" ]]; then
    neovim_args+=(--cmd "let \$NVD_TMUX_ORIGIN_PANE = '${NVD_TMUX_ORIGIN_PANE}'")
  fi

  if [[ -n "${NVD_TMUX_ORIGIN_WINDOW:-}" ]]; then
    neovim_args+=(--cmd "let \$NVD_TMUX_ORIGIN_WINDOW = '${NVD_TMUX_ORIGIN_WINDOW}'")
  fi

  if [[ -n "${NVD_KITTY_ORIGIN_WINDOW:-}" ]]; then
    neovim_args+=(--cmd "let \$NVD_KITTY_ORIGIN_WINDOW = '${NVD_KITTY_ORIGIN_WINDOW}'")
  fi

  if [[ -n "${NVD_KITTY_TARGET_WINDOW:-}" ]]; then
    neovim_args+=(--cmd "let \$NVD_KITTY_TARGET_WINDOW = '${NVD_KITTY_TARGET_WINDOW}'")
  fi

  if [[ -n "${NVD_KITTY_LISTEN_ON:-}" ]]; then
    neovim_args+=(--cmd "let \$NVD_KITTY_LISTEN_ON = '${NVD_KITTY_LISTEN_ON}'")
  fi

  if (( ${#neovim_args[@]} > 0 )); then
    neovide_args+=(-- "${neovim_args[@]}")
  fi

  if [[ "$use_macos_app" == true ]]; then
    neovide_cmd=("$open_bin" -W -n -b com.neovide.neovide --args "${neovide_args[@]}")
  else
    neovide_cmd=("$bin" "${neovide_args[@]}")
  fi

  {
    print -r -- '#!/usr/bin/env zsh'
    print -r -- 'setopt no_unset'
    print -r -- 'trap "rm -f -- $0" EXIT'
    _nvd_capture_gui_env
    print -r -- "cd -- ${(q)cwd} || exit 1"
    print -r -- "$(_nvd_quote_args "${neovide_cmd[@]}")"
    for line in "${on_exit_lines[@]}"; do
      print -r -- "$line"
    done
  } >| "$script"

  chmod +x "$script"
  print -r -- "$script"
}

_nvd_run_blocking_neovide() {
  local script
  local zsh_bin

  zsh_bin="$(command -v zsh)" || return 1
  script="$(_nvd_make_blocking_neovide_script "$@")" || return 1

  tmux run-shell -b "$(_nvd_quote_args "$zsh_bin" "$script")"
}

_nvd_restore_from_neovide() {
  local cwd="$1"
  shift

  local session_id
  local window_id
  local window_name
  local tmux_bin
  local restore_window

  tmux_bin="$(command -v tmux)" || return 1
  session_id="$(_nvd_tmux_value '#{session_id}')"
  window_id="$(_nvd_tmux_value '#{window_id}')"
  window_name="$(_nvd_tmux_value '#{window_name}')"

  [[ -n "$session_id" && -n "$window_id" ]] || return 1

  restore_window="$(_nvd_quote_args "$tmux_bin" new-window -t "$session_id" -c "$cwd" -n "$window_name")"

  _nvd_run_blocking_neovide "$cwd" "$restore_window" -- "$@" || return 1
  tmux kill-window -t "$window_id"
}

_nvd_restore_pane_from_neovide() {
  local cwd="$1"
  shift

  local pane_id
  local pane_count
  local tmux_bin
  local window_id
  local window_layout
  local pane_left
  local pane_top
  local pane_width
  local pane_height
  local window_width
  local window_height
  local restore_pane
  local -a on_exit_lines
  local -a join_args

  tmux_bin="$(command -v tmux)" || return 1
  pane_id="$(_nvd_tmux_value '#{pane_id}')"
  pane_count="$(_nvd_tmux_value '#{window_panes}')"
  window_id="$(_nvd_tmux_value '#{window_id}')"
  window_layout="$(_nvd_tmux_value '#{window_layout}')"
  pane_left="$(_nvd_tmux_value '#{pane_left}')"
  pane_top="$(_nvd_tmux_value '#{pane_top}')"
  pane_width="$(_nvd_tmux_value '#{pane_width}')"
  pane_height="$(_nvd_tmux_value '#{pane_height}')"
  window_width="$(_nvd_tmux_value '#{window_width}')"
  window_height="$(_nvd_tmux_value '#{window_height}')"

  [[ -n "$pane_id" && -n "$window_id" && "$pane_count" == <-> ]] || return 1

  join_args=("$tmux_bin" join-pane -d -s "$pane_id" -t "$window_id")

  if [[ "$pane_width" == <-> && "$window_width" == <-> && "$pane_width" -lt "$window_width" ]]; then
    join_args+=(-h)
    [[ "$pane_left" == <-> && "$pane_left" -eq 0 ]] && join_args+=(-b)
  elif [[ "$pane_height" == <-> && "$window_height" == <-> && "$pane_height" -lt "$window_height" ]]; then
    join_args+=(-v)
    [[ "$pane_top" == <-> && "$pane_top" -eq 0 ]] && join_args+=(-b)
  fi

  restore_pane="$(_nvd_quote_args "${join_args[@]}")"

  on_exit_lines+=("if $(_nvd_quote_args "$tmux_bin" display-message -p -t "$window_id" '#{window_id}') >/dev/null 2>&1 \\")
  on_exit_lines+=("  && $(_nvd_quote_args "$tmux_bin" display-message -p -t "$pane_id" '#{pane_id}') >/dev/null 2>&1; then")
  on_exit_lines+=("  $restore_pane")
  if [[ -n "$window_layout" ]]; then
    on_exit_lines+=("  $(_nvd_quote_args "$tmux_bin" select-layout -t "$window_id" "$window_layout") 2>/dev/null || true")
  fi
  on_exit_lines+=("fi")

  if ! NVD_TMUX_ORIGIN_PANE="$pane_id" \
    NVD_TMUX_ORIGIN_WINDOW="$window_id" \
    _nvd_run_blocking_neovide "$cwd" "${on_exit_lines[@]}" -- "$@"; then
    return 1
  fi

  # 把当前 pane 搬进隐藏 session 停放：tab 上不再冒出 nvd:@xxx window
  # join-pane 恢复时用全局唯一的 $pane_id 引用，跨 session 一样能拉回原窗口
  if _nvd_tmux_ensure_park_session; then
    tmux break-pane -d -s "$pane_id" -t "=$_NVD_TMUX_PARK_SESSION:" -n "nvd:$window_id"
  else
    # 隐藏 session 建不出来时退回原行为，至少保证 pane 不丢
    tmux break-pane -d -s "$pane_id" -n "nvd:$window_id"
  fi
}

_nvd_restore_kitty_from_neovide() {
  local cwd="$1"
  shift

  local bun_bin
  local kitten_bin
  local zsh_bin
  local plan
  local script
  local restore_window
  local fallback_window

  bun_bin="$(command -v bun)" || return 1
  kitten_bin="$(command -v kitten)" || return 1
  zsh_bin="$(command -v zsh)" || return 1

  # Kitty 没有 tmux break-pane/join-pane 等价能力：
  # - 先在当前 tab/OS window 里找到非 Vim 的 AI window，并固定为 Neovide 的发送目标
  # - 后台启动阻塞 Neovide，再关闭源 Kitty window，达到“近似隐藏”
  # - Neovide 退出后在目标 window 所在 tab 旁边重开 cwd window；布局位置只能近似恢复
  plan="$("$bun_bin" run "$HOME/.config/kitty/scripts/nvd-plan.ts")" || return 1
  eval "$plan"

  [[ -n "${NVD_KITTY_LISTEN_ON:-}" ]] || return 1
  [[ -n "${NVD_KITTY_ORIGIN_WINDOW:-}" ]] || return 1
  [[ -n "${NVD_KITTY_TARGET_WINDOW:-}" ]] || return 1
  [[ -n "${NVD_KITTY_RESTORE_LOCATION:-}" ]] || NVD_KITTY_RESTORE_LOCATION='vsplit'

  restore_window="$(_nvd_quote_args \
    "$kitten_bin" @ --to "$NVD_KITTY_LISTEN_ON" \
    launch \
    --match "window_id:$NVD_KITTY_TARGET_WINDOW" \
    --type=window \
    --cwd "$cwd" \
    --location "$NVD_KITTY_RESTORE_LOCATION" \
    --next-to "id:$NVD_KITTY_TARGET_WINDOW")"

  fallback_window="$(_nvd_quote_args \
    "$kitten_bin" @ --to "$NVD_KITTY_LISTEN_ON" \
    launch \
    --type=window \
    --cwd "$cwd")"

  script="$(NVD_KITTY_LISTEN_ON="$NVD_KITTY_LISTEN_ON" \
    NVD_KITTY_ORIGIN_WINDOW="$NVD_KITTY_ORIGIN_WINDOW" \
    NVD_KITTY_TARGET_WINDOW="$NVD_KITTY_TARGET_WINDOW" \
    _nvd_make_blocking_neovide_script \
      "$cwd" \
      "$restore_window >/dev/null 2>&1 || $fallback_window >/dev/null 2>&1 || true" \
      -- \
      "$@")" || return 1

  "$kitten_bin" @ --to "$NVD_KITTY_LISTEN_ON" launch --type=background "$zsh_bin" "$script" >/dev/null || return 1
  "$kitten_bin" @ --to "$NVD_KITTY_LISTEN_ON" close-window --match "id:$NVD_KITTY_ORIGIN_WINDOW" --ignore-no-match >/dev/null 2>&1
}

_nvd_cwd() {
  if [[ -n "$TMUX_PANE" ]] && command -v tmux &>/dev/null; then
    local pane_cwd
    pane_cwd=$(tmux display-message -p -t "$TMUX_PANE" '#{pane_current_path}' 2>/dev/null)
    if [[ -n "$pane_cwd" && -d "$pane_cwd" ]]; then
      print -r -- "$pane_cwd"
      return
    fi
  fi

  print -r -- "$PWD"
}

nvd() {
  local cwd="$(_nvd_cwd)"
  local -a args
  local -a launch_args
  args=("$@")

  if (( $# == 1 )) && [[ -d "$1" ]]; then
    cwd="${1:A}"
    args=()
  fi

  launch_args=()

  if ! _neovide_app_available; then
    launch_args+=(--fork)
  fi

  # macOS 上 Neovide 默认不用 sRGB，和 kitty / alacritty 等终端的观感可能不一致；
  # 只在 macOS 启用，避免影响 Linux/Wayland 下已经正常的颜色路径
  if is_mac && _neovide_supports_arg '--srgb'; then
    launch_args+=(--srgb)
  fi

  # 不同平台 / 发行版打包的 Neovide CLI 参数不完全一致
  # 每次启动前按当前二进制的 help 动态判断，避免同步到其他系统后启动失败
  if _neovide_supports_arg '--reuse-instance'; then
    launch_args+=(--reuse-instance)
  fi

  if _neovide_supports_arg '--new-window'; then
    launch_args+=(--new-window)
  fi

  launch_args+=(--chdir "$cwd")

  if _nvd_tmux_can_replace_window; then
    _nvd_restore_from_neovide "$cwd" "${args[@]}"
    return
  fi

  if _nvd_tmux_can_replace_pane; then
    _nvd_restore_pane_from_neovide "$cwd" "${args[@]}"
    return
  fi

  if _nvd_kitty_can_replace_window; then
    _nvd_restore_kitty_from_neovide "$cwd" "${args[@]}" && return
  fi

  _neovide_launch "${launch_args[@]}" "${args[@]}"
}
