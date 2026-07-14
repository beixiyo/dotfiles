#!/usr/bin/env bash
# 切换 WiFi 开关：读当前 radio 状态后反转，并用 mako 通知反馈
# 绑定于 waybar network 模块左键

state=$(nmcli -t radio wifi)

if [ "$state" = "enabled" ]; then
  nmcli radio wifi off
  notify-send -i network-wireless-offline "WiFi" "已关闭"
else
  nmcli radio wifi on
  notify-send -i network-wireless "WiFi" "已开启"
fi
