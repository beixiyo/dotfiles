#!/usr/bin/env bash
set -u

bat=${WAYBAR_BATTERY_BAT:-/sys/class/power_supply/BAT0}
ac=${WAYBAR_BATTERY_AC:-/sys/class/power_supply/AC}

read_file() {
  local path=$1

  if [[ -r $path ]]; then
    tr -d '\n' < "$path"
  fi
}

json_escape() {
  local value=${1//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/}
  value=${value//$'\t'/\\t}

  printf '%s' "$value"
}

format_watts() {
  local microwatts=$1

  awk -v value="$microwatts" 'BEGIN { printf "%.1fW", value / 1000000 }'
}

format_health() {
  local full=$1
  local design=$2

  if [[ -n $full && -n $design && $design -gt 0 ]]; then
    awk -v full="$full" -v design="$design" 'BEGIN { printf "%.0f%%", full * 100 / design }'
  else
    printf '%s' '--'
  fi
}

if [[ ! -d $bat ]]; then
  text='󰂑 --'
  tooltip='未找到 BAT0'
  printf '{"text":"%s","tooltip":"%s","class":"missing"}\n' \
    "$(json_escape "$text")" \
    "$(json_escape "$tooltip")"
  exit 0
fi

capacity=$(read_file "$bat/capacity")
status=$(read_file "$bat/status")
power_now=$(read_file "$bat/power_now")
energy_now=$(read_file "$bat/energy_now")
energy_full=$(read_file "$bat/energy_full")
energy_full_design=$(read_file "$bat/energy_full_design")
charge_full=$(read_file "$bat/charge_full")
charge_full_design=$(read_file "$bat/charge_full_design")
ac_online=$(read_file "$ac/online")

capacity=${capacity:-0}
status=${status:-Unknown}
power_now=${power_now:-0}

icons=(󰂎 󰁺 󰁻 󰁼 󰁽 󰁾 󰁿 󰂀 󰂂 󰁹)
icon_index=$((capacity / 10))
if ((icon_index > 9)); then
  icon_index=9
fi

icon=${icons[$icon_index]}
class='normal'

case $status in
  Charging)
    icon='󰂄'
    class='charging'
    ;;
  Full)
    class='full'
    ;;
  Discharging)
    if ((capacity <= 15)); then
      class='critical'
    elif ((capacity <= 30)); then
      class='warning'
    fi
    ;;
  *)
    if [[ $ac_online == 1 ]]; then
      class='plugged'
    fi
    ;;
esac

power=$(format_watts "$power_now")

if [[ -n $energy_full || -n $energy_full_design ]]; then
  health=$(format_health "${energy_full:-0}" "${energy_full_design:-0}")
else
  health=$(format_health "${charge_full:-0}" "${charge_full_design:-0}")
fi

text="$icon ${capacity}%"
tooltip=$(printf '剩余：%s%%\n状态：%s\n功率：%s\n健康度：%s' \
  "$capacity" \
  "$status" \
  "$power" \
  "$health")

printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' \
  "$(json_escape "$text")" \
  "$(json_escape "$tooltip")" \
  "$(json_escape "$class")"
