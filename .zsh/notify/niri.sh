#!/usr/bin/env bash
# niri.sh — niri wayland 合成器集成：焦点判断、窗口聚焦、事件流监听
# 被 main.sh source，不可单独执行

# _niri_up: niri + jq 均可用且 NIRI_SOCKET 已设置时返回 0
_niri_up() {
  [[ -n "$NIRI_SOCKET" ]] && command -v niri &>/dev/null && command -v jq &>/dev/null
}

# _focused_is_terminal: 当前 niri 聚焦窗口的 app_id 是终端时返回 0
_focused_is_terminal() {
  local _app
  _app=$(niri msg --json focused-window 2>/dev/null | jq -r '.app_id // empty')
  _app=${_app,,}
  [[ "$_app" == *ghostty* || "$_app" == *wezterm* || "$_app" == *kitty* \
     || "$_app" == *foot* || "$_app" == *alacritty* ]]
}

# _focus_terminal: 按 _TERM_APPS 优先级聚焦终端窗口（niri → KWin → wmctrl → xdotool）
# 逐个候选用子串匹配，命中第一个有窗口的终端即聚焦；不再写死单一终端
_focus_terminal() {
  local _app

  # niri：一次取全部窗口，按优先级逐个匹配 app_id
  if _niri_up; then
    local _wins _id
    _wins=$(niri msg --json windows 2>/dev/null)
    for _app in "${_TERM_APPS[@]}"; do
      _id=$(printf '%s' "$_wins" | jq -r --arg a "$_app" \
        'map(select(.app_id != null and (.app_id | ascii_downcase | contains($a)))) | .[0].id // empty')
      if [[ -n "$_id" ]]; then
        niri msg action focus-window --id "$_id" 2>/dev/null
        return
      fi
    done
  fi

  # KDE (KWin) 回退：把优先级列表内联进脚本，按序命中第一个即聚焦
  if command -v qdbus6 &>/dev/null; then
    local _tmp _script_name _js_apps
    _tmp=$(mktemp /tmp/focus-term-XXXX.js)
    _script_name="focus-term-$$"
    _js_apps=$(printf '"%s",' "${_TERM_APPS[@]}")
    cat > "$_tmp" << KWIN
var apps = [${_js_apps}];
var wins = workspace.windowList ? workspace.windowList() : workspace.clientList();
outer:
for (var a = 0; a < apps.length; a++) {
    for (var i = 0; i < wins.length; i++) {
        if (wins[i].resourceClass.toString().toLowerCase().indexOf(apps[a]) >= 0) {
            workspace.activeWindow = wins[i];
            break outer;
        }
    }
}
KWIN
    qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$_tmp" "$_script_name" &>/dev/null
    qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.start &>/dev/null
    sleep 0.3
    qdbus6 org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript "$_script_name" &>/dev/null
    rm -f "$_tmp"
    return
  fi

  # X11 回退：wmctrl / xdotool，同样按优先级逐个尝试
  if command -v wmctrl &>/dev/null; then
    for _app in "${_TERM_APPS[@]}"; do
      wmctrl -xa "$_app" 2>/dev/null && return
    done
  elif command -v xdotool &>/dev/null; then
    local _wid
    for _app in "${_TERM_APPS[@]}"; do
      _wid=$(xdotool search --classname "$_app" 2>/dev/null | head -1)
      if [[ -n "$_wid" ]]; then
        xdotool windowactivate "$_wid" 2>/dev/null && return
      fi
    done
  fi
}
