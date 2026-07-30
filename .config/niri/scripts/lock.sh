#!/usr/bin/env sh
# 统一锁屏入口：Swayidle 的 lock、timeout 和 before-sleep 都调用 Noctalia
#
# 用法：
#   lock.sh          请求锁屏后立即返回
#   lock.sh --wait   等待会话真正锁定，供 before-sleep 使用
#
# Noctalia 不可用或未能及时取得 session lock 时，仍以 Hyprlock 安全回退
# 所有入口先检查 LockedHint，避免重复请求和嵌套 locker

session_is_locked() {
  [ "$(loginctl show-session auto -p LockedHint --value 2>/dev/null)" = yes ]
}

request_noctalia_lock() {
  # 服务可能仍处于登录启动阶段，先确保 unit 已启动，再短暂等待 IPC 就绪
  systemctl --user start noctalia.service >/dev/null 2>&1 || return 1

  n=0
  while [ "$n" -lt 20 ]; do
    noctalia msg session lock >/dev/null 2>&1 && return 0
    n=$((n + 1))
    sleep 0.1
  done

  return 1
}

start_hyprlock_fallback() {
  pidof hyprlock >/dev/null 2>&1 || setsid -f hyprlock
}

wait_until_locked() {
  # logind 的 InhibitDelayMaxSec 通常只有 5 秒，不能无限阻塞
  n=0
  while [ "$n" -lt "$1" ]; do
    session_is_locked && return 0
    n=$((n + 1))
    sleep 0.1
  done

  return 1
}

if ! session_is_locked; then
  request_noctalia_lock || start_hyprlock_fallback
fi

# 普通 lock/timeout 回调不阻塞 Swayidle 的事件循环
[ "${1:-}" = "--wait" ] || exit 0

# Noctalia 正常情况下几十毫秒即可锁定；3 秒后仍失败则启动 Hyprlock 回退
wait_until_locked 30 && exit 0
start_hyprlock_fallback
wait_until_locked 15

# 旧 Hyprlock-only 实现（保留作人工回退）：
#   pidof hyprlock >/dev/null 2>&1 || setsid -f hyprlock
#   [ "${1:-}" = "--wait" ] || exit 0
#   等待 LockedHint=yes，最多 1.5 秒
