# 登录 shell 环境：niri-session 以 `$SHELL -l` 重新执行后，用 systemctl --user import-environment
# 把整份环境导入 systemd 用户环境（会覆盖 environment.d 的 PATH），Niri 及其启动的应用由此继承
# ~/.local/bin 追加在末尾：图形程序优先使用系统命令（如 wl-copy）；交互 shell 的 env.zsh 会再将其前置
typeset -U path PATH
path+=("$HOME/.local/bin")
export PATH
