# 把当前脚本路径先转成绝对路径，再取它的目录
local _zsh_functions_dir="${${(%):-%x}:A:h}"

# 剪贴板检测依赖 check.zsh 的环境判断，先于检测链加载
source "$_zsh_functions_dir/utils/index.zsh"

## 跨平台剪贴板（各文件直接引用 _CLIP_COPY / _CLIP_PASTE）
# 后端由 _actions/clip.sh 每次执行时现场选择（OSC52 / pbcopy / ...），
# 避免 shell 启动后再被 ssh attach 时仍沿用启动时的结论；无可用后端时置空，调用方据此报错
if "$_zsh_functions_dir/_actions/clip.sh" available; then
  _CLIP_COPY="$_zsh_functions_dir/_actions/clip.sh copy"
  _CLIP_PASTE="$_zsh_functions_dir/_actions/clip.sh paste"
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
