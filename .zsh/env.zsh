# ── 平台检测 ──────────────────────────────────────────────
# isMac / isWSL: 供后续条件分支使用
[[ "$(uname -s)" == Darwin ]] && export isMac=1 || export isMac=0
[[ -f /proc/sys/fs/binfmt_misc/WSLInterop || -n "$WSL_DISTRO_NAME" ]] && export isWSL=1 || export isWSL=0


# ── 修饰键映射（fzf 等统一用）─────────────────────────────
# fzf 的 --bind 只认 ctrl/alt，故 fzfOptionBind/fzfCmdBind 为实际绑定值
if [[ "$isMac" -eq 1 ]]; then
  export optionKey="option"
  export cmdKey="cmd"
  export fzfOptionBind="alt"   # fzf 不支持 option
  export fzfCmdBind="ctrl"     # 终端里 Cmd 一般不送进 fzf
else
  export optionKey="alt"
  export cmdKey="ctrl"
  export fzfOptionBind="alt"
  export fzfCmdBind="ctrl"
fi


# ── WSL 专属 ─────────────────────────────────────────────
if [[ "$isWSL" -eq 1 ]]; then
  # Mesa OpenGL → D3D12（避免退回 llvmpipe 软件渲染）
  export GALLIUM_DRIVER=d3d12
  # VA-API → D3D12（ffmpeg 等用 GPU 做视频编解码）
  export LIBVA_DRIVER_NAME=d3d12
  # 默认浏览器（调用 Windows 侧）
  export BROWSER='cmd.exe /c start'
  # Windows 侧 VSCode/Cursor 路径
  PATH="/mnt/c/Develop/Microsoft\ VS\ Code/bin:$PATH"
fi


# ── 编辑器 ───────────────────────────────────────────────
# 优先级 nvim > vim > code；code 必须带 -w（wait）否则 git commit / crontab -e 等会以为瞬间编辑完
# MANPAGER 仅 nvim 有等价支持，vim/code 不设
if command -v nvim &>/dev/null; then
  export EDITOR="nvim"
  export MANPAGER="nvim +Man!"
elif command -v vim &>/dev/null; then
  export EDITOR="vim"
elif command -v code &>/dev/null; then
  export EDITOR="code -w"
fi


# ── PATH ─────────────────────────────────────────────────
# 用户命令、Neovim 托管工具与自带脚本（clean-trailing 等 CLI）
typeset -U path PATH
path=(
  "$HOME/.local/bin"
  "$HOME/.config/nvim/scripts"
  $path
)
export PATH


# ── fzf ──────────────────────────────────────────────────
# 用 fd 替代默认 find（快、智能、跳过忽略文件）
if command -v fd &>/dev/null; then
  export FZF_DEFAULT_COMMAND='fd --type f --color=always --strip-cwd-prefix --hidden --follow --no-ignore-parent --exclude .git --exclude node_modules'
  export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
fi

# Catppuccin Theme
# export FZF_DEFAULT_OPTS=" \
# --color=bg+:#313244,bg:#1E1E2E,spinner:#F5E0DC,hl:#F38BA8 \
# --color=fg:#CDD6F4,header:#F38BA8,info:#CBA6F7,pointer:#F5E0DC \
# --color=marker:#B4BEFE,fg+:#CDD6F4,prompt:#CBA6F7,hl+:#F38BA8 \
# --color=selected-bg:#45475A \
# --color=border:#6C7086,label:#CDD6F4"

# Tokyo Night Theme
export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS \
  --highlight-line \
  --info=inline-right \
  --ansi \
  --layout=reverse \
  --border=none \
  --color=bg+:#2d3f76 \
  --color=bg:#1e2030 \
  --color=border:#589ed7 \
  --color=fg:#c8d3f5 \
  --color=gutter:#1e2030 \
  --color=header:#ff966c \
  --color=hl+:#65bcff \
  --color=hl:#65bcff \
  --color=info:#545c7e \
  --color=marker:#ff007c \
  --color=pointer:#ff007c \
  --color=prompt:#65bcff \
  --color=query:#c8d3f5:regular \
  --color=scrollbar:#589ed7 \
  --color=separator:#ff966c \
  --color=spinner:#ff007c \
"


# ── Proxy（国内镜像）────────────────────────────────────
export GOPROXY="https://goproxy.cn,direct"
# export npm_config_registry="https://registry.npmmirror.com"
export PIP_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple"


# ── Homebrew（仅在安装时生效）─────────────────────────────
if command -v brew &>/dev/null; then
  export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.ustc.edu.cn/brew.git"
  export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.ustc.edu.cn/homebrew-core.git"
  export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles"
  export HOMEBREW_API_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles/api"
fi


# ── 中文环境 ─────────────────────────────────────────────
# export LANG=zh_CN.UTF-8
# export LC_ALL=zh_CN.UTF-8


# V8 缓存优化，主要用于 Electron
export NODE_COMPILE_CACHE=~/.cache/node-compile-cache
