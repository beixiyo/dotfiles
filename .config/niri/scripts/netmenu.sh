#!/usr/bin/env bash
# fuzzel WiFi 选择器 — 跟随 matugen 配色，风格同 powermenu.sh
# 扫描 / 连接 / 输密码 / 开关，全部走 fuzzel UI
# 绑定于 waybar network 模块左键

FZ=(fuzzel --dmenu --prompt "网络 ❯ " --width 34)

# 同一 synchronous 标签：loading 通知会被后续结果通知原地替换，不会堆叠
TAG=(-h string:x-canonical-private-synchronous:wifi-menu)
notify()  { notify-send "${TAG[@]}" -i "$1" "WiFi" "$2"; }
loading() { notify-send "${TAG[@]}" -i network-wireless -t 0 "WiFi" "$1"; }  # -t 0 不自动消失，等结果替换

# 信号强度 → Nerd Font 图标
# 阈值对齐 waybar 内部算法（5 档 = signal/20 取整 → 20/40/60/80）
sig_icon() {
  local s=${1:-0}
  if   [ "$s" -ge 80 ]; then echo "󰤨"
  elif [ "$s" -ge 60 ]; then echo "󰤥"
  elif [ "$s" -ge 40 ]; then echo "󰤢"
  elif [ "$s" -ge 20 ]; then echo "󰤟"
  else                       echo "󰤯"; fi
}

# WiFi 关闭时：只给「开启」一项
if [ "$(nmcli -t radio wifi)" != "enabled" ]; then
  pick=$(printf '󰖩  开启 WiFi' | "${FZ[@]}" --lines 1)
  [ -n "$pick" ] && nmcli radio wifi on && notify network-wireless "已开启"
  exit 0
fi

# 后台触发扫描（不阻塞本次菜单，让下次打开/刷新更准）
nmcli device wifi rescan >/dev/null 2>&1 &

# 构建菜单：固定项 + 扫描到的网络（同名去重保留最强，按信号降序）
# 关键：--rescan no 用缓存秒开，避免阻塞等待整轮扫描（默认会卡 10s+）
declare -A SSID_OF
menu=$'󰖪  关闭 WiFi\n󰑐  重新扫描\n──────────────'
seen=

while IFS=: read -r inuse ssid signal security; do
  [ -z "$ssid" ] && continue
  case "$seen" in *"|$ssid|"*) continue ;; esac
  seen="$seen|$ssid|"

  icon=$(sig_icon "$signal")
  lock=" "; [ -n "$security" ] && lock="󰌾"
  mark="";  [ "$inuse" = "*" ] && mark="  󰄬"
  line="$icon  $ssid  $lock$mark"

  SSID_OF["$line"]="$ssid"
  menu="$menu"$'\n'"$line"
done < <(nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY device wifi list --rescan no 2>/dev/null | sort -t: -k3 -nr)

choice=$(printf '%s' "$menu" | "${FZ[@]}" --lines 12)
[ -z "$choice" ] && exit 0

case "$choice" in
  '󰖪  关闭 WiFi')   nmcli radio wifi off && notify network-wireless-offline "已关闭"; exit 0 ;;
  '󰑐  重新扫描')
    loading "󰑐  正在扫描…"
    nmcli device wifi rescan 2>/dev/null
    notify network-wireless "扫描完成"
    exec "$0" ;;
  '──────────────') exit 0 ;;
esac

ssid="${SSID_OF[$choice]}"
[ -z "$ssid" ] && exit 0

# 已保存的连接 → 直接激活
if nmcli -t -f NAME connection show | grep -qxF "$ssid"; then
  loading "󱛇  正在连接 $ssid…"
  nmcli connection up id "$ssid" >/dev/null 2>&1 \
    && notify network-wireless "已连接 $ssid" \
    || notify network-error "连接 $ssid 失败"
  exit 0
fi

# 新网络：加密则弹密码框（--rescan no 用缓存，避免阻塞）
secured=$(nmcli -t -f SSID,SECURITY device wifi list --rescan no \
  | awk -F: -v s="$ssid" '$1==s && $2!=""{print 1; exit}')

if [ -n "$secured" ]; then
  pass=$(printf '' | "${FZ[@]}" --password --lines 0 --prompt "$ssid 密码 ❯ ")
  [ -z "$pass" ] && exit 0
  loading "󱛇  正在连接 $ssid…"
  nmcli device wifi connect "$ssid" password "$pass" >/dev/null 2>&1 \
    && notify network-wireless "已连接 $ssid" \
    || notify network-error "连接 $ssid 失败（密码错误？）"
else
  loading "󱛇  正在连接 $ssid…"
  nmcli device wifi connect "$ssid" >/dev/null 2>&1 \
    && notify network-wireless "已连接 $ssid" \
    || notify network-error "连接 $ssid 失败"
fi
