# 把当前脚本路径先转成绝对路径，再取它的目录
local _zsh_functions_dir="${${(%):-%x}:A:h}"

## 跨平台剪贴板（统一检测，各文件直接引用 _CLIP_COPY / _CLIP_PASTE）
if command -v pbcopy &>/dev/null; then
  _CLIP_COPY='pbcopy'
  _CLIP_PASTE='pbpaste'
elif [[ -n "$WSL_DISTRO_NAME" || -n "$WSLENV" ]] || { [[ -r /proc/version ]] && grep -qi microsoft /proc/version; }; then
  _CLIP_COPY='clip.exe'
  _CLIP_PASTE='powershell.exe -NoProfile -Command Get-Clipboard'
elif command -v wl-copy &>/dev/null; then
  _CLIP_COPY='wl-copy'
  _CLIP_PASTE='wl-paste'
elif command -v xclip &>/dev/null; then
  _CLIP_COPY='xclip -selection clipboard'
  _CLIP_PASTE='xclip -selection clipboard -o'
elif command -v xsel &>/dev/null; then
  _CLIP_COPY='xsel --clipboard --input'
  _CLIP_PASTE='xsel --clipboard --output'
else
  _CLIP_COPY=''
  _CLIP_PASTE=''
fi

source "$_zsh_functions_dir/utils/index.zsh"
source "$_zsh_functions_dir/file-ops.zsh"
source "$_zsh_functions_dir/fzf.zsh"
source "$_zsh_functions_dir/git.zsh"
source "$_zsh_functions_dir/yazi.zsh"

source "$_zsh_functions_dir/process.zsh"
source "$_zsh_functions_dir/docker.zsh"
source "$_zsh_functions_dir/dev.zsh"
source "$_zsh_functions_dir/neovide.zsh"
source "$_zsh_functions_dir/proxy.zsh"
source "$_zsh_functions_dir/ssh.zsh"

source "$_zsh_functions_dir/net.zsh"
source "$_zsh_functions_dir/download.zsh"
source "$_zsh_functions_dir/mihomo.zsh"
source "$_zsh_functions_dir/sys.zsh"

source "$_zsh_functions_dir/pkg/_common.zsh"
source "$_zsh_functions_dir/pkg/install.zsh"
source "$_zsh_functions_dir/pkg/update.zsh"
source "$_zsh_functions_dir/pkg/uninstall.zsh"
source "$_zsh_functions_dir/pkg/viewer.zsh"
