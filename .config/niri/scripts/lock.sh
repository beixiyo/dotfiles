#!/usr/bin/env sh
# 锁屏入口：swayidle 的 lock / timeout / before-sleep 三个回调统一走这里
#
# 为什么不能直接写 "pidof hyprlock || hyprlock"：
#   swayidle 带 -w 时 cmd_exec 只 fork 一次，然后在【唯一的事件循环里】同步 waitpid
#   （swayidle 1.9.0 main.c:141-178），而 hyprlock 没有 -f/daemonize 选项，
#   于是从锁屏那一刻起 swayidle 整个冻结，niri 照常发出的 idled 事件全堆在
#   wayland socket 缓冲区里没人读；解锁后一次性补跑：
#     timeout 900  → hyprlock 刚死，pidof 落空 → 重新锁屏（嵌套锁屏）
#     timeout 1020 → 无条件关屏          → 解锁瞬间黑一下
#     timeout 120  → hyprlock 已死，&& 短路 → 锁屏后自动息屏永远不发生
#   这里用 setsid -f 把 hyprlock 甩给 init，swayidle 立刻拿回事件循环
#
# 用法：
#   lock.sh          启动后立即返回（lock / timeout 回调用）
#   lock.sh --wait   阻塞到会话真正锁上，最多 1.5s（before-sleep 回调用）

# 已有实例时不重复启动，但 --wait 仍需等待它真正取得 session lock
if ! pidof hyprlock >/dev/null 2>&1; then
  # -f 额外 fork 一次并新建 session，hyprlock 被 init 收养，不随 swayidle 进程组连坐
  setsid -f hyprlock
fi

# 非 --wait 直接返回，把事件循环还给 swayidle
[ "${1:-}" = "--wait" ] || exit 0

# before-sleep 场景：等 niri 把 logind LockedHint 置 yes，确认画面已被 ext-session-lock 接管
# 必须有上限：logind 的 InhibitDelayMaxSec 只有 5s，无限等会重新把事件循环卡死
n=0
while [ "$n" -lt 15 ]; do
  [ "$(loginctl show-session auto -p LockedHint --value 2>/dev/null)" = yes ] && exit 0
  n=$((n + 1))
  sleep 0.1
done

exit 0
