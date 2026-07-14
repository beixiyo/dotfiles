#!/bin/bash

# 锁屏脚本 - 跨平台支持
# 支持: macOS · GNOME · KDE · Niri · Hyprland · Sway · 其他 logind 环境
#
# macOS 权限：
#   主路径不依赖辅助功能权限；仅 osascript 回退路径需要触发方具备辅助功能权限
#
# Linux 依赖（按优先级，任意一项即可）：
#   loginctl（systemd）· gnome-screensaver · qdbus（KDE）
#   hyprlock · swaylock · waylock · gtklock

KEEP_AWAKE_SECS=3600  # 锁屏后保持亮屏时长（秒）

# ── macOS ─────────────────────────────────────────────────────────────────

lock_macos() {
  # 防止锁屏后立即息屏
  nohup caffeinate -d -t "$KEEP_AWAKE_SECS" >/dev/null 2>&1 &

  # 优先使用系统锁屏入口，不依赖 Accessibility / TCC 的按键注入权限
  local cg_session="/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession"
  if [[ -x "$cg_session" ]]; then
    "$cg_session" -suspend && return
  fi

  # 新版 macOS 可能没有 CGSession；启动屏幕保护程序通常不需要辅助功能权限
  local screen_saver="/System/Library/CoreServices/ScreenSaverEngine.app/Contents/MacOS/ScreenSaverEngine"
  if [[ -x "$screen_saver" ]]; then
    open -a ScreenSaverEngine && return
  fi

  # 回退：Ctrl+Cmd+Q 是 macOS 原生锁屏快捷键
  osascript -e 'tell application "System Events" to keystroke "q" using {control down, command down}'
}

# ── Linux: 保持亮屏 ────────────────────────────────────────────────────────

keep_awake_linux() {
  # systemd-inhibit 阻止系统进入 idle，Wayland/X11 通用
  if command -v systemd-inhibit &>/dev/null; then
    nohup systemd-inhibit \
      --what=idle \
      --who="lock-screen" \
      --why="锁屏后保持亮屏" \
      sleep "$KEEP_AWAKE_SECS" >/dev/null 2>&1 &
    return
  fi

  # X11 回退：临时禁用 DPMS 电源管理
  if [[ -n "$DISPLAY" ]] && command -v xset &>/dev/null; then
    nohup bash -c "xset -dpms s off; sleep $KEEP_AWAKE_SECS; xset +dpms s on" \
      >/dev/null 2>&1 &
  fi
}

# ── Linux: 锁屏 ───────────────────────────────────────────────────────────

lock_linux() {
  local locked=false

  # 1. loginctl lock-session
  #    兼容所有集成 systemd-logind 的环境：
  #    GNOME · KDE · Niri · Hyprland · Sway · XFCE · LXQt …
  #    注意：loginctl 只发 D-Bus 信号，退出 0 ≠ 已锁屏；
  #    需要合成器（如 Niri + swayidle lock 事件）实际处理信号
  if command -v loginctl &>/dev/null; then
    loginctl lock-session
    sleep 0.5
    if loginctl show-session 2>/dev/null | grep -q "LockedHint=yes"; then
      locked=true
    fi
  fi

  # 2. GNOME screensaver（GNOME 专属回退）
  if ! $locked && command -v gnome-screensaver-command &>/dev/null; then
    gnome-screensaver-command --lock && locked=true
  fi

  # 3. KDE via DBus
  if ! $locked && command -v qdbus &>/dev/null; then
    qdbus org.kde.screensaver /ScreenSaver \
      org.freedesktop.ScreenSaver.Lock 2>/dev/null && locked=true
  fi

  # 4. Wayland locker 直接调用
  #    适用于 Niri / Hyprland / Sway 等已配置独立锁屏程序的环境
  if ! $locked; then
    for locker in hyprlock swaylock waylock gtklock; do
      if command -v "$locker" &>/dev/null; then
        "$locker" >/dev/null 2>&1 &
        locked=true
        break
      fi
    done
  fi

  if ! $locked; then
    echo "❌ 未找到可用的锁屏命令，请安装以下任一程序：" >&2
    echo "   loginctl（systemd）/ gnome-screensaver / swaylock / hyprlock / waylock" >&2
    exit 1
  fi

  # 锁屏后 0.5 秒关屏（让 swayidle 接管后续息屏/唤醒）
  if command -v niri &>/dev/null; then
    sleep 0.5 && niri msg action power-off-monitors &
  fi
}

# ── 入口 ──────────────────────────────────────────────────────────────────

case "$(uname -s)" in
  Darwin) lock_macos ;;
  Linux)  lock_linux  ;;
  *)
    echo "❌ 不支持的操作系统: $(uname -s)" >&2
    exit 1
    ;;
esac
