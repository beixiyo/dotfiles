# Interactive package viewer: list installed packages with fzf
# Usage: pkgs

pkgs() {
  local pm
  if is_mac && has brew; then
    pm=brew
  elif has apt; then
    pm=apt
  elif has pacman; then
    pm=pacman
  else
    log_err "no supported package manager found (brew/apt/pacman)"
    return 1
  fi

  local clip="${_CLIP_COPY:-tee /dev/null}"

  local preview_cmd uninstall_cmd files_cmd path_cmd
  case $pm in
    pacman)
      preview_cmd='pacman -Qi {1}'
      uninstall_cmd='sudo pacman -Rns {+1}'
      files_cmd='pacman -Ql {1}'
      path_cmd='pacman -Ql {1} | head -1 | cut -d" " -f2'
      ;;
    apt)
      preview_cmd='dpkg -s {1} 2>/dev/null'
      uninstall_cmd='sudo apt remove {+1}'
      files_cmd='dpkg -L {1}'
      path_cmd='dpkg -L {1} | grep bin/ | head -1'
      ;;
    brew)
      preview_cmd='brew info {1}'
      uninstall_cmd='brew uninstall {+1}'
      files_cmd='brew list {1}'
      path_cmd='brew --prefix {1}'
      ;;
  esac

  require bun || return 1

  local _dir="${${(%):-%x}:A:h}"
  local _list_ts="${_dir}/../bun/src/pkg/list.ts"
  _list_ts="${_list_ts:A}"
  local gen_list="bun run ${_list_ts} --pm=$pm 2>/dev/null"

  local header
  header="Info ↵ │ Multi ⇥ │ Uninstall ^D │ Copy name ${_fzf_opt_hint}C"
  header+=$'\n'"Copy path ${_fzf_opt_hint}P │ Files ^F │ Refresh ^R"

  eval "$gen_list" < /dev/null | fzf --ansi --multi \
    --delimiter '\t' \
    --with-nth '2..' \
    --prompt "$pm> " \
    --header "$header" \
    --preview "$preview_cmd" \
    --preview-window 'right:45%:wrap' \
    --bind "${_fzf_scroll_binds}" \
    --bind "enter:execute($preview_cmd | less < /dev/tty > /dev/tty)" \
    --bind "ctrl-d:execute(echo 'Confirm uninstall {+1}? (y/N) ' && read -r ans < /dev/tty && [ \"\$ans\" = y ] && $uninstall_cmd < /dev/tty > /dev/tty 2>&1)+reload:$gen_list < /dev/null" \
    --bind "alt-c:execute-silent(echo -n {+1} | $clip)" \
    --bind "alt-p:execute-silent($path_cmd | tr -d '\\n' | $clip)" \
    --bind "ctrl-f:execute($files_cmd | less < /dev/tty > /dev/tty)" \
    --bind "ctrl-r:reload:$gen_list < /dev/null"
}
