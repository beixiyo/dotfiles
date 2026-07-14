#!/usr/bin/env bash
# linux.sh — Linux notify-send 通知 + 智能自动消除
# 被 main.sh source，不可单独执行

# _kill_tree <pid>: 自底向上递归 kill 进程子树
# 回收 watcher 时，它可能正阻塞在 `niri msg` / `sleep` 子进程上；先收叶子再收根，
# 避免先 kill 父进程导致在途子进程被 reparent 走而残留
_kill_tree() {
  local _p="$1" _c
  for _c in $(pgrep -P "$_p" 2>/dev/null); do
    _kill_tree "$_c"
  done
  kill "$_p" 2>/dev/null
}

# _notify_close <notification_id>: 经 D-Bus 关闭指定通知
# 注意：仅 kill 掉 notify-send 客户端进程【不会】让服务端（mako 等）撤回 -t 0 的通知，
# 通知是服务端状态，必须显式调用 CloseNotification 才会从屏幕消失（且 notify-send --wait 随之退出）
_notify_close() {
  local _id="$1"
  [[ -n "$_id" ]] || return

  busctl --user call org.freedesktop.Notifications /org/freedesktop/Notifications \
    org.freedesktop.Notifications CloseNotification u "$_id" &>/dev/null && return

  gdbus call --session --dest org.freedesktop.Notifications \
    --object-path /org/freedesktop/Notifications \
    --method org.freedesktop.Notifications.CloseNotification "$_id" &>/dev/null
}

# _enforce_notification_cap: 本 app 在屏通知超过 NOTIFY_MAX 时，关掉最旧的若干条（FIFO）
# mako id 单调递增 ⇒ id 越小越旧。关闭最旧的会让其 notify-send --wait 退出 → 连进程一起回收
# 解析的是本机 makoctl list 的【文本】输出（非 JSON）：
#   Notification <id>: <summary>
#     App name: <app>
# 默认上限 10，可用 NOTIFY_MAX 调整；NOTIFY_MAX=0 关闭该限制
_enforce_notification_cap() {
  local _max="${NOTIFY_MAX:-10}"
  [[ "$_max" =~ ^[0-9]+$ ]] || return
  (( _max <= 0 )) && return
  command -v makoctl &>/dev/null || return

  # 取本 app（claude-code）所有通知 id，升序（旧→新）
  local _ids
  _ids=$(makoctl list 2>/dev/null | awk '
    /^Notification [0-9]+:/ { id = $2; sub(/:$/, "", id) }
    /^[[:space:]]+App name: / {
      app = $0; sub(/^[[:space:]]+App name: /, "", app)
      if (app == "claude-code") print id
    }' | sort -n)

  local _count
  _count=$(printf '%s\n' "$_ids" | grep -c .)
  (( _count <= _max )) && return

  # 关掉最旧的 (_count - _max) 条
  local _excess=$(( _count - _max )) _id
  while (( _excess > 0 )) && IFS= read -r _id; do
    [[ -n "$_id" ]] || continue
    _notify_close "$_id"
    _excess=$(( _excess - 1 ))
  done <<< "$_ids"
}

# _notify_linux <desc> <body> <saved_pane> <tmux_socket>
# 发出 notify-send 通知；用户切回 Claude 所在 tmux pane 时自动关闭通知；点击「跳转」按钮则切换 pane + 聚焦终端
_notify_linux() {
  local desc="$1"
  local body="$2"
  local saved_pane="$3"
  local tmux_socket="$4"

  (
    local _tmp _idf
    _tmp=$(mktemp /tmp/notify-action-XXXX)
    _idf=$(mktemp /tmp/notify-id-XXXX)

    # 统一有限超时：到点自动消失。绝不用 -t 0——它让 notify-send --wait 永久阻塞，
    # 配合「watcher 到期不关闭」会导致通知与进程双双堆积泄漏（niri/mako 下尤甚）
    # 有限超时下 notify-send 必然自退 → wait 返回 → watcher 被回收 → 零泄漏
    # tmux 内仍保留「回到原 pane 即提前关闭」的 watcher（见下），只是不再永久挂着
    # 默认 15min（900000ms）：够长，AFK/睡觉时也不易错过完成；但仍有限 → 不泄漏
    # 可用 NOTIFY_TIMEOUT 覆盖（毫秒），如临时想短一点 NOTIFY_TIMEOUT=8000
    local _timeout="${NOTIFY_TIMEOUT:-900000}"

    # --id-fd 3：通知 ID 写入 _idf（用于后续 CloseNotification）；
    # stdout(_tmp) 仅承载被点击时的 action 名，二者分离不互相污染
    # 动作键用 default：mako 左键点击通知体即触发跳转（见 on-button-left）
    # -a claude-code：固定 app-name，既让 mako 按 app 分组更准，也给「通知上限」一个过滤句柄
    notify-send -a "claude-code" -t "$_timeout" "$desc" "$body" \
      --action="default=↩ 跳转到终端" \
      --id-fd 3 --wait >"$_tmp" 3>"$_idf" 2>/dev/null &
    local _npid=$!

    # 读取通知 ID（mako 注册需极短时间，轮询兜底，最多约 1s）
    local _nid= _i=0
    while [[ -z "$_nid" && $_i -lt 20 ]]; do
      _nid=$(cat "$_idf" 2>/dev/null)
      [[ -n "$_nid" ]] && break
      sleep 0.05
      _i=$((_i + 1))
    done

    # 通知上限：新通知已注册（_nid 就绪即在册），此刻清掉超额的最旧通知（FIFO）
    _enforce_notification_cap

    # tmux 下：后台 watcher 监听「用户切回原终端窗口」，命中即【提前】关闭通知
    # （通知本身已有有限超时会自消失，watcher 只是把「人回来了」这件事变成立即关闭，
    #  不再是泄漏的来源——即便 watcher 什么都没干，超时也会让 notify-send 自退并回收 watcher）
    # 后台轮询：用户【真正回到 Claude 所在的 tmux pane】（且终端窗口处于焦点）时才关闭通知
    # _user_present 综合判断「niri 焦点在终端窗口」+「tmux 活动 pane == 本 pane」，精确到具体
    # window-pane——只切到终端窗口却停在别的 pane（如 %3≠%2）不会误关，这正是 mac/kde 的粒度
    # main.sh 已保证发通知时 _user_present=false，故首次变 true 即真实回归，无需去抖
    # deadline 仅覆盖通知显示窗口（超时即止），避免短超时下空转
    local _watcher=
    if [[ -n "$saved_pane" && -n "$tmux_socket" ]]; then
      (
        _deadline=$(( SECONDS + _timeout / 1000 + 2 ))
        while kill -0 "$_npid" 2>/dev/null && (( SECONDS < _deadline )); do
          if _user_present; then
            _notify_close "$_nid"
            break
          fi
          sleep 0.5
        done
      ) &
      _watcher=$!
    fi

    # 阻塞直到通知被点击 / 被 watcher 关闭 / 自然超时（关闭后 notify-send 自然退出）
    wait "$_npid" 2>/dev/null

    # 通知已结束 → 回收 watcher 整棵子树（含 timeout/niri/jq），避免残留孤儿
    [[ -n "$_watcher" ]] && _kill_tree "$_watcher"

    local _action
    _action=$(cat "$_tmp" 2>/dev/null)
    rm -f "$_tmp" "$_idf"

    if [[ "$_action" == "default" ]]; then
      _switch_tmux_pane "$saved_pane" "$tmux_socket"
      _focus_terminal
    fi
  ) </dev/null >/dev/null 2>&1 &
  disown $!
}
