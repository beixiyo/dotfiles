# Find File / Find String (fzf)
# fzf command building in bun/src/ff-cmd.ts / fs-cmd.ts

() {
  local dir="${${(%):-%x}:A:h}"
  _FZF_BUN="$dir/bun/src"

  local cmd="${fzfCmdBind:-ctrl}"
  _fzf_scroll_binds="${cmd}-n:down,${cmd}-p:up,ctrl-e:preview-down+preview-down+preview-down+preview-down+preview-down,ctrl-y:preview-up+preview-up+preview-up+preview-up+preview-up"
}

ff() { require bun || return 1; bun run "$_FZF_BUN/ff-cmd.ts" "$@"; }

fs() { require bun || return 1; bun run "$_FZF_BUN/fs-cmd.ts" "$@"; }

fx() { require bun || return 1; bun run "$_FZF_BUN/fx-cmd.ts" "$@"; }


# Tab 补全预览：cd/rm 用 lsd 预览目录，code/vim 等用 bat 预览文件
if command -v fzf &>/dev/null; then
  _fzf_comprun() {
    local command=$1; shift
    local _dir_cmds=(cd rm)
    local _file_cmds=(code vim nvim vi bat cat nano)

    if (($_dir_cmds[(Ie)$command])); then
      fzf --preview '(command -v lsd &>/dev/null && lsd --tree --depth 2 --color always --icon always --group-directories-first -a {} || ls -la {}) | head -200' "$@"
    elif (($_file_cmds[(Ie)$command])); then
      fzf --preview '(command -v bat &>/dev/null && bat --color=always --style=numbers --line-range=:500 {} || cat {})' "$@"
    else
      fzf "$@"
    fi
  }
fi
