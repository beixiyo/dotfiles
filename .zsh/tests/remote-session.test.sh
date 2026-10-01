#!/usr/bin/env bash
# remote-session.test.sh — 远程会话判定一致性测试
#
# 被测实现（判据必须一致）：
#   shell 侧：~/.local/bin/remote-session（notify / check.zsh / clip.sh 都经由它）
#   Lua 侧：  ~/.config/nvim/vendors/vv-utils.nvim/lua/vv-utils/sys/remote.lua（插件自包含的另一份实现）
#
# 做法：起两个隔离的 tmux server（不碰用户正在用的 server）
#   target server：被测对象，client 连到这里
#   host server：给模拟的 client 进程提供终端；同时作为“祖先链干净”的执行环境
#     （tmux server 的父进程是 launchd / init，不受运行测试者自己是否经 SSH 登录影响）
# 构造进程名为 sshd-session / mosh-server 的假远程进程：
#   macOS 用 exec -a 改 argv0（ps comm 随之改变）；Linux 的 comm 来自内核、只认可执行文件名，
#   改用复制出的 bash（macOS 上复制系统二进制会被签名校验杀掉）
#
# 场景：
#   tmux client：A sshd-session → tmux；B sshd-session → zsh → tmux；M mosh-server → tmux；
#                C 本地 bash → tmux；D A + C 并存
#   不在 tmux：自身进程链（环境变量清空，只有祖先链能暴露远程）；仅环境变量
#
# 用法：bash ~/.zsh/tests/remote-session.test.sh   全部通过退出码 0

set -u

# 清掉调用者自己的 SSH 环境，避免污染 host server 的全局环境
unset SSH_CONNECTION SSH_TTY SSH_CLIENT

RS="$HOME/.local/bin/remote-session"
VV="$HOME/.config/nvim/vendors/vv-utils.nvim"
CLIP="$HOME/.zsh/functions/_actions/clip.sh"
NOTIFY_TMUX="$HOME/.zsh/notify/tmux.sh"
CHECK_ZSH="$HOME/.zsh/functions/utils/check.zsh"

work=$(mktemp -d "${TMPDIR:-/tmp}/remote-session-test.XXXXXX")
T="$work/target.sock"
H="$work/host.sock"
fail=0

cleanup() {
  tmux -S "$H" kill-server 2>/dev/null
  tmux -S "$T" kill-server 2>/dev/null
  rm -rf "$work"
}
trap cleanup EXIT

# fake <name>：输出以 <name> 为进程名运行 bash 的命令前缀
fake() {
  if [[ "$(uname)" == Darwin ]]; then
    printf 'exec -a %s bash' "$1"
  else
    [[ -x "$work/$1" ]] || cp /bin/bash "$work/$1"
    printf "exec '%s'" "$work/$1"
  fi
}

check() {
  local name="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    printf '  ok    %-56s %s\n' "$name" "$got"
  else
    printf '  FAIL  %-56s got=%s want=%s\n' "$name" "$got" "$want"
    fail=1
  fi
}

rc() { "$@" >/dev/null 2>&1; echo $?; }

# Lua 实现的两个查询，写成脚本文件，便于在任意进程链下执行
cat > "$work/lua-clients.sh" <<EOF
nvim --headless -u NONE --cmd "set rtp+=$VV" -c "lua local r = require('vv-utils.sys.remote'); local out = {}; for _, c in ipairs(r.tmux_clients() or {}) do out[#out+1] = c.pid .. ' ' .. (c.remote and 'remote' or 'local') end; table.sort(out); io.write(table.concat(out, ','))" -c 'qa!' 2>&1
EOF
cat > "$work/lua-is-remote.sh" <<EOF
nvim --headless -u NONE --cmd "set rtp+=$VV" -c "lua io.write(require('vv-utils.sys.remote').is_remote() and 'remote' or 'local')" -c 'qa!' 2>&1
EOF
lua_clients() { bash "$work/lua-clients.sh"; }
lua_is_remote() { bash "$work/lua-is-remote.sh"; }

bash_clients() { "$RS" clients | awk '{print $1, $2}' | sort | paste -sd, -; }

# run_clean <script>：在 host server 的新窗口（祖先链干净）里执行脚本，输出其 stdout
# 在 $(...) 子 shell 里调用，计数器传不回来，故用 mktemp 取唯一文件名
run_clean() {
  local f
  f=$(mktemp "$work/clean.XXXXXX")
  printf '%s\n' "$1" > "$f.sh"
  tmux -S "$H" new-window -d -t host "bash '$f.sh' > '$f.out' 2>&1; touch '$f.done'"
  local i
  for i in $(seq 1 100); do [[ -e "$f.done" ]] && break; sleep 0.1; done
  cat "$f.out"
}

# attach_client <name> <script>：在 host server 里起一个窗口运行 script（最终 attach 到 target）
# script 里 $T 为 target socket；末尾的 `; :` 防止 shell 把最后一条命令 exec 掉、丢失中间进程
attach_client() {
  printf '%s\n' "$2" > "$work/$1.sh"
  tmux -S "$H" new-window -d -t host -n "$1" "T='$T' bash '$work/$1.sh'"
}

wait_clients() {
  local want="$1" i
  for i in $(seq 1 50); do
    [[ "$(tmux -S "$T" list-clients 2>/dev/null | wc -l | tr -d ' ')" == "$want" ]] && return 0
    sleep 0.1
  done
  echo "  timeout waiting for $want clients" >&2
  fail=1
}

detach_all() {
  local c
  for c in $(tmux -S "$T" list-clients -F '#{client_name}' 2>/dev/null); do tmux -S "$T" detach-client -t "$c"; done
  wait_clients 0
}

# run_case <label> <client kinds> <expect tmux-any> <expect tmux-all>
run_case() {
  local label="$1" kind="$2" want_any="$3" want_all="$4"
  echo "== $label"
  export TMUX="$T,0,0"
  local b l
  b=$(bash_clients); l=$(lua_clients)
  check "bash/lua 逐 client 分类一致" "$b" "$l"
  check "client 分类为 $kind" "$(echo "$b" | tr ',' '\n' | awk '{print $2}' | sort -u | paste -sd, -)" "$kind"
  check "remote-session tmux-any" "$(rc "$RS" tmux-any)" "$want_any"
  check "remote-session tmux-all" "$(rc "$RS" tmux-all)" "$want_all"
  check "vv-utils is_remote 与 tmux-any 一致" "$(lua_is_remote)" "$([[ $want_any == 0 ]] && echo remote || echo local)"
  check "notify _is_remote_session" "$(rc bash -c "source '$NOTIFY_TMUX'; _tmux_socket='$T'; _is_remote_session")" "$want_any"
  check "check.zsh is_tmux_ssh_attached" "$(rc zsh -fc "source '$CHECK_ZSH'; is_tmux_ssh_attached")" "$want_any"
  check "clip.sh backend" "$(SSH_TTY='' "$CLIP" backend)" "$([[ $want_any == 0 ]] && echo osc52 || SSH_TTY='' TMUX='' "$CLIP" backend)"
  unset TMUX
}

tmux -S "$T" -f /dev/null new-session -d -s t
tmux -S "$H" -f /dev/null new-session -d -s host -x 120 -y 40
SSHD=$(fake sshd-session)
MOSH=$(fake mosh-server)
ATTACH='TMUX= tmux -S "$T" attach -t t; :'

echo "== 无 client"
check "tmux-any 无 client → 2" "$(TMUX="$T,0,0" rc "$RS" tmux-any)" 2
check "vv-utils tmux_clients 无 client → nil" "$(TMUX="$T,0,0" nvim --headless -u NONE --cmd "set rtp+=$VV" -c "lua io.write(tostring(require('vv-utils.sys.remote').tmux_clients()))" -c 'qa!' 2>&1)" nil

attach_client A "$SSHD -c '$ATTACH'"
wait_clients 1
run_case "A  sshd-session → tmux" remote 0 0
detach_all

attach_client B "$SSHD -c 'zsh -fc \"TMUX= tmux -S \\\"\$T\\\" attach -t t; :\"; :'"
wait_clients 1
run_case "B  sshd-session → zsh → tmux" remote 0 0
detach_all

attach_client M "$MOSH -c '$ATTACH'"
wait_clients 1
run_case "M  mosh-server → tmux" remote 0 0
detach_all

attach_client C "exec bash -c '$ATTACH'"
wait_clients 1
run_case "C  bash → tmux（本地）" local 1 1
detach_all

attach_client A2 "$SSHD -c '$ATTACH'"
attach_client C2 "exec bash -c '$ATTACH'"
wait_clients 2
run_case "D  A + C 同时在连" local,remote 0 1
detach_all

echo "== 不在 tmux：自身进程链（环境变量清空，只有祖先链能暴露远程）"
self_case() {
  local label="$1" prefix="$2" want="$3"
  # unset 而非置空：不在 tmux 时 TMUX 根本未定义（曾因 set -u 下直接读 $TMUX 而报错退出）
  local env='unset TMUX; export SSH_CONNECTION= SSH_TTY= SSH_CLIENT='
  check "${label}：remote-session any" \
    "$(run_clean "$env; $prefix -c '\"\$0\" any >/dev/null 2>&1; echo \$?; :' '$RS'")" "$want"
  check "${label}：vv-utils is_remote" \
    "$(run_clean "$env; $prefix -c 'bash \"\$0\"; :' '$work/lua-is-remote.sh'")" "$([[ $want == 0 ]] && echo remote || echo local)"
}
self_case "在 sshd-session 之下" "$SSHD" 0
self_case "在 mosh-server 之下" "$MOSH" 0
self_case "本地（无远程祖先）" "exec bash" 1

echo "== 不在 tmux：环境变量兜底（祖先链干净时）"
env_case() {
  local label="$1" conn="$2" tty="$3" want="$4"
  local env="unset TMUX; export SSH_CONNECTION='$conn' SSH_TTY='$tty'"
  check "${label}：remote-session any" "$(run_clean "$env; '$RS' any >/dev/null 2>&1; echo \$?")" "$want"
  check "${label}：vv-utils is_remote" "$(run_clean "$env; bash '$work/lua-is-remote.sh'")" "$([[ $want == 0 ]] && echo remote || echo local)"
}
env_case "SSH_CONNECTION 远端地址" '10.0.0.3 51234 10.0.0.4 22' '' 0
env_case "SSH_CONNECTION 两端回环" '127.0.0.1 51234 127.0.0.1 22' '' 1
env_case "SSH_CONNECTION=tmux（cx 伪造值）" 'tmux' '' 1
env_case "只有 SSH_TTY" '' '/dev/ttys001' 0
env_case "都没有" '' '' 1

echo
if (( fail )); then echo "FAILED"; exit 1; fi
echo "ALL PASSED"
