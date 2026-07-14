#!/usr/bin/env bash
# 壁纸自动循环切换（配合 awww-daemon 使用）
# 用法：wallpaper-cycle.sh [壁纸目录] [切换间隔秒数]
# 示例：wallpaper-cycle.sh ~/Pictures/wallpapers 600

# 壁纸目录，默认 ~/Pictures
WALLPAPER_DIR="${1:-$HOME/Pictures}"
# 轮播间隔（秒）
INTERVAL="${2:-600}"
# 过渡动画类型：wipe / left / right / top / bottom / center / fade / grow / outer / random / wave / simple
TRANSITION="random"
# 过渡动画时长（秒）
TRANSITION_DURATION=2

# overview 模糊壁纸缓存目录
OVERVIEW_CACHE="$HOME/.cache/overview-blur"
mkdir -p "$OVERVIEW_CACHE"
BLUR_STRENGTH="0x15"
DARKEN_AMOUNT="40%"

sleep 1

FIRST=true
while true; do
  for img in "$WALLPAPER_DIR"/*.{jpg,jpeg,png,webp,gif}; do
    [ -f "$img" ] || continue
    awww img "$img" --transition-type "$TRANSITION" --transition-duration "$TRANSITION_DURATION"

    # 记录当前壁纸路径（hyprlock 锁屏背景用）
    ln -sf "$img" "$HOME/.cache/.current_wallpaper"

    # overview 背景：模糊+压暗
    blur_file="$OVERVIEW_CACHE/$(basename "$img").jpg"
    if [ ! -f "$blur_file" ]; then
      magick "${img}[0]" -blur "$BLUR_STRENGTH" -fill black -colorize "$DARKEN_AMOUNT" "$blur_file"
    fi
    awww img -n overview "$blur_file" --transition-type fade --transition-duration 0.5

    # Material You 配色提取，更新 waybar/mako/niri 颜色
    # 首次同步执行（确保 colors.css 存在），之后后台执行
    # 非首次先冻结画面，让 niri 配色热重载在冻结帧后面完成，避免布局重算抖动
    if [ "$FIRST" = true ]; then
      matugen image "$img" --prefer saturation -q
      FIRST=false
    else
      niri msg action do-screen-transition --delay-ms 600
      matugen image "$img" --prefer saturation -q &
    fi
    sleep "$INTERVAL"
  done
done
