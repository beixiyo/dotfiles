# 把当前脚本路径先转成绝对路径，再取它的目录
local _zsh_functions_dir="${${(%):-%x}:A:h}"

# 剪贴板检测依赖 check.zsh 的环境判断，先于检测链加载
source "$_zsh_functions_dir/utils/index.zsh"

## 跨平台剪贴板（统一检测，各文件直接引用 _CLIP_COPY / _CLIP_PASTE）
# OSC52 会被 tmux 广播给所有 attach 的客户端，本地终端与 ssh 对端各写各的剪贴板；
# 因此「被 ssh 登录的远程机」或「本地 tmux 被 ssh attach」时统一走 OSC52
if [[ -x "$_zsh_functions_dir/_actions/osc52.sh" ]] && {
     [[ -n "${SSH_TTY:-}" && -z "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]] || is_tmux_ssh_attached
   }; then
  _CLIP_COPY="$_zsh_functions_dir/_actions/osc52.sh copy"
  _CLIP_PASTE="$_zsh_functions_dir/_actions/osc52.sh paste"
elif command -v pbcopy &>/dev/null; then
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

source "$_zsh_functions_dir/hosts/init.zsh"
source "$_zsh_functions_dir/net.zsh"
source "$_zsh_functions_dir/download.zsh"
source "$_zsh_functions_dir/mihomo.zsh"
source "$_zsh_functions_dir/sys.zsh"

source "$_zsh_functions_dir/pkg/_common.zsh"
source "$_zsh_functions_dir/pkg/install.zsh"
source "$_zsh_functions_dir/pkg/update.zsh"
source "$_zsh_functions_dir/pkg/uninstall.zsh"
source "$_zsh_functions_dir/pkg/viewer.zsh"
