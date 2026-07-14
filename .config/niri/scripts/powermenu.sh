#!/bin/bash
options="锁屏\n注销\n重启\n关机"
choice=$(echo -e "$options" | fuzzel --dmenu --prompt "电源 ❯ " --lines 4 --width 15)

case "$choice" in
  锁屏) loginctl lock-session ;;
  注销) niri msg action quit ;;
  重启)
    confirm=$(echo -e "否\n是" | fuzzel --dmenu --prompt "确定重启？ " --lines 2 --width 15)
    [ "$confirm" = "是" ] && systemctl reboot
    ;;
  关机)
    confirm=$(echo -e "否\n是" | fuzzel --dmenu --prompt "确定关机？ " --lines 2 --width 15)
    [ "$confirm" = "是" ] && systemctl poweroff
    ;;
esac
