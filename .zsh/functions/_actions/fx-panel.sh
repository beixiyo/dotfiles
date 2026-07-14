#!/usr/bin/env bash
# Channel switching panel for fx (unified fzf entry)
# Config: /tmp/fzf-fx-env (written by fx-cmd.ts)
#
# Subcommands:
#   init                - render header, output initial actions
#   header              - render channel tabs
#   footer              - render action bar for current channel
#   switch-next Q       - switch to next channel
#   switch-prev Q       - switch to prev channel
#   enter ITEM          - dispatch enter for current channel
#   click WORD ITEM     - handle footer click

[[ -f /tmp/fzf-fx-env ]] && source /tmp/fzf-fx-env

SCRIPT="${BASH_SOURCE[0]}"
CH_STATE="/tmp/fzf-fx-channel"

CHANNELS=("Files" "Grep")
CH_COUNT=${#CHANNELS[@]}

FUNC_DIR="$_FX_FUNC_DIR"
BUN_SRC="$_FX_BUN_SRC"
DIR="$_FX_DIR"
CLIP_CMD="$_FX_CLIP_CMD"

RG_BASE="rg --column --line-number --no-heading --color=never --smart-case --hidden --no-ignore-parent"
[[ -n "$_FX_RG_NO_IGNORE" ]] && RG_BASE+=" $_FX_RG_NO_IGNORE"
RG_BASE+=" --glob '!.git'"

ch_get() {
  local v
  v=$(cat "$CH_STATE" 2>/dev/null) || v=0
  [[ "$v" =~ ^[0-9]+$ ]] || v=0
  ((v >= CH_COUNT)) && v=0
  echo "$v"
}

ch_put() { echo "$1" > "$CH_STATE"; }

render_header() {
  local pos="$1" out="" i
  for i in "${!CHANNELS[@]}"; do
    ((i > 0)) && out+=" │"
    if ((i == pos)); then
      out+=$'\e[1;7m'" ${CHANNELS[$i]} "$'\e[0m'
    else
      out+=" ${CHANNELS[$i]} "
    fi
  done
  echo "$out"
}

FOOTER_ACTIONS=("Select" "Code" "nvim" "Copy")

render_footer() {
  local i out=""
  for i in "${!FOOTER_ACTIONS[@]}"; do
    ((i > 0)) && out+=" │"
    if ((i == 0)); then
      out+=$'\e[1;7m'" ${FOOTER_ACTIONS[$i]} "$'\e[0m'
    else
      out+=" ${FOOTER_ACTIONS[$i]} "
    fi
  done
  echo "$out"
}

ff_reload() {
  local ni="${_FX_NO_IGNORE:+ $_FX_NO_IGNORE}"
  echo "bun run '${BUN_SRC}/ff-list.ts' --dir '${DIR}' --type a${ni} 2>/dev/null < /dev/null"
}

fs_reload_with_query() {
  local query="$1"
  echo "${RG_BASE} $(printf '%q' "$query") '${DIR}' < /dev/null | bun run '${BUN_SRC}/fs-list.ts' 2>/dev/null || true"
}

switch_to() {
  local ch="$1" query="$2"
  ch_put "$ch"

  local actions=""
  case $ch in
    0) # Files
      actions="enable-search"
      actions+="+unbind(change)"
      actions+="+change-prompt( Files> )"
      actions+="+reload($(ff_reload))"
      actions+="+change-preview(${FUNC_DIR}/_preview/ff.sh {2})"
      ;;
    1) # Grep
      actions="disable-search"
      actions+="+rebind(change)"
      actions+="+change-prompt( Grep> )"
      actions+="+reload($(fs_reload_with_query "$query"))"
      actions+="+change-preview(${FUNC_DIR}/_preview/fs.sh {2})"
      ;;
  esac
  actions+="+transform-header(${SCRIPT} header)"
  actions+="+transform-footer(${SCRIPT} footer)"
  echo "$actions"
}

dispatch_enter() {
  local item="$1"
  local ch
  ch=$(ch_get)
  case $ch in
    0) printf "become(%s %s '%s/path.ts')" \
         "$FUNC_DIR/_actions/ff-select.sh" \
         "$(printf '%q' "$item")" \
         "$BUN_SRC" ;;
    1) printf "become(%s %s '%s/path.ts')" \
         "$FUNC_DIR/_actions/fs-select.sh" \
         "$(printf '%q' "$item")" \
         "$BUN_SRC" ;;
  esac
}

dispatch_click() {
  local word="$1" item="$2"
  local ch file line
  ch=$(ch_get)
  case "$word" in
    Select)
      dispatch_enter "$item" ;;
    Code)
      case $ch in
        0) printf "execute(code %s)" "$(printf '%q' "$item")" ;;
        1) file="${item%%:*}"; line="${item#*:}"; line="${line%%:*}"
           printf "execute(code -g %s:%s)" "$(printf '%q' "$file")" "$line" ;;
      esac ;;
    nvim)
      case $ch in
        0) printf "execute(nvim %s < /dev/tty)" "$(printf '%q' "$item")" ;;
        1) file="${item%%:*}"; line="${item#*:}"; line="${line%%:*}"
           printf "execute(nvim '+%s' %s < /dev/tty)" "$line" "$(printf '%q' "$file")" ;;
      esac ;;
    Copy)
      printf "execute-silent(bun run '%s/path.ts' abs %s 2>/dev/null | %s)" \
        "$BUN_SRC" "$(printf '%q' "$item")" "$CLIP_CMD" ;;
  esac
}

case "$1" in
  init)
    ch_put 0
    render_header 0
    ;;
  header)
    render_header "$(ch_get)"
    ;;
  footer)
    render_footer
    ;;
  switch-next)
    p=$(ch_get); ((p=(p+1)%CH_COUNT))
    switch_to "$p" "$2"
    ;;
  switch-prev)
    p=$(ch_get); ((p=(p-1+CH_COUNT)%CH_COUNT))
    switch_to "$p" "$2"
    ;;
  enter)
    dispatch_enter "$2"
    ;;
  click)
    dispatch_click "$2" "$3"
    ;;
esac
