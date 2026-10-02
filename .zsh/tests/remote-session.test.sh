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
#   -t target：target 所属 session 有远程 client / 只有本地 client / target 不存在（退出码 2 ↔ nil）
#   ps 不可用（PATH 前置总是失败的假 ps，远程 client 在连）：tmux 判定为“判不出”，按环境变量兜底，ps 只调一次
#   不在 tmux：自身进程链（环境变量清空，只有祖先链能暴露远程）；ps 不可用时按环境变量；仅环境变量
#   在 tmux 但无 client：退回自身进程链
#   每个 vv-utils is_remote 检查都同时跑 is_remote_async，两者结论不一致即失败
#   OpenSSH 9.8+ 改写的进程名（含冒号、空格、斜杠，如 "sshd-session: es@pts/0"）作 client 祖先 / 自身祖先：
#     判据必须先取第一个词再取 basename，否则 basename 取到 "0" 判成本地
#     （去结尾冒号一步不影响 sshd* / mosh-server* 前缀判定，结论不变，无法也无需在此覆盖）
#     仅 macOS 覆盖：Linux 的 ps comm 来自内核（可执行文件名），不随进程标题改写，也无法含斜杠
#
# 用法：bash ~/.zsh/tests/remote-session.test.sh   全部通过退出码 0
#   remote-session 经 `#!/usr/bin/env bash` 取 PATH 上的 bash；验证 macOS 自带 bash 3.2：
#   PATH=/bin:$PATH /bin/bash ~/.zsh/tests/remote-session.test.sh（开头会打印实际使用的 bash 版本）

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
# lua-clients：tmux_clients({ target = $RS_TARGET })；返回 nil 时输出 nil
cat > "$work/lua-clients.sh" <<EOF
nvim --headless -u NONE --cmd "set rtp+=$VV" -c "lua local r = require('vv-utils.sys.remote'); local cs = r.tmux_clients({ target = vim.env.RS_TARGET }); if not cs then io.write('nil') return end; local out = {}; for _, c in ipairs(cs) do out[#out+1] = c.pid .. ' ' .. (c.remote and 'remote' or 'local') end; table.sort(out); io.write(table.concat(out, ','))" -c 'qa!' 2>&1
EOF
# lua-is-remote：同时跑 is_remote 与 is_remote_async，一致时输出 remote / local，否则输出 mismatch(...)
cat > "$work/lua-is-remote.lua" <<EOF
vim.opt.rtp:prepend('$VV')
local r = require('vv-utils.sys.remote')
local function word(v) return v and 'remote' or 'local' end
local sync = r.is_remote()
local async
r.is_remote_async(function(v) async = v end)
vim.wait(3000, function() return async ~= nil end)
if async == sync then
  io.write(word(sync))
else
  io.write(('mismatch(sync=%s,async=%s)'):format(word(sync), async == nil and 'timeout' or word(async)))
end
EOF
cat > "$work/lua-is-remote.sh" <<EOF
nvim --headless -u NONE -l '$work/lua-is-remote.lua' 2>&1
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

echo "remote-session 解释器：$(env bash -c 'echo "bash $BASH_VERSION"')"

tmux -S "$T" -f /dev/null new-session -d -s t
tmux -S "$H" -f /dev/null new-session -d -s host -x 120 -y 40
SSHD=$(fake sshd-session)
MOSH=$(fake mosh-server)
# 改写后的进程标题（仅 macOS 可构造，见文件头）；为空表示跳过相关场景
SSHD_TITLE=""
[[ "$(uname)" == Darwin ]] && SSHD_TITLE="exec -a 'sshd-session: es@pts/0' bash"
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

if [[ -n "$SSHD_TITLE" ]]; then
  attach_client E "$SSHD_TITLE -c '$ATTACH'"
  wait_clients 1
  run_case "E  'sshd-session: es@pts/0' → tmux" remote 0 0
  detach_all
else
  echo "== E  跳过：改写后的进程标题仅 macOS 可构造"
fi

echo "== -t target（只看 target 所属 session 的 client）"
# session t 由远程 client 连着，session u 只有本地 client
tmux -S "$T" new-session -d -s u
PANE_T=$(tmux -S "$T" display -p -t t: '#{pane_id}')
PANE_U=$(tmux -S "$T" display -p -t u: '#{pane_id}')
ATTACH_U='TMUX= tmux -S "$T" attach -t u; :'
attach_client TA "$SSHD -c '$ATTACH'"
attach_client TU "exec bash -c '$ATTACH_U'"
wait_clients 2
# target_case <label> <target> <want tmux-any> <want 分类（target 不存在时为 nil）>
target_case() {
  local label="$1" target="$2" want_any="$3" want_kind="$4" b l kind
  export TMUX="$T,0,0"
  b=$("$RS" -t "$target" clients | awk '{print $1, $2}' | sort | paste -sd, -)
  l=$(RS_TARGET="$target" lua_clients)
  check "${label}：bash/lua 分类一致（空 ↔ nil）" "${b:-nil}" "$l"
  kind=nil
  [[ -n "$b" ]] && kind=$(echo "$b" | tr ',' '\n' | awk '{print $2}' | sort -u | paste -sd, -)
  check "${label}：分类为 $want_kind" "$kind" "$want_kind"
  check "${label}：remote-session -t tmux-any" "$(rc "$RS" -t "$target" tmux-any)" "$want_any"
  unset TMUX
}
target_case "target=session t 的 pane（远程 client）" "$PANE_T" 0 remote
target_case "target=session u 的 pane（仅本地 client）" "$PANE_U" 1 local
target_case "target 不存在" '%999999' 2 nil
detach_all
tmux -S "$T" kill-session -t u

echo "== ps 不可用（远程 client 在连；进程链信息不可用 → 按环境变量兜底）"
# 假 ps：记录调用次数后失败。shell 与 nvim 的 vim.system 都按 PATH 找 ps
mkdir -p "$work/fakeps"
cat > "$work/fakeps/ps" <<EOF
#!/bin/sh
echo call >> '$work/ps-calls'
exit 1
EOF
chmod +x "$work/fakeps/ps"
# no_ps [VAR=val...] <cmd...>：在假 ps + target server 的环境下执行，先清零调用计数
no_ps() { rm -f "$work/ps-calls"; env PATH="$work/fakeps:$PATH" TMUX="$T,0,0" "$@"; }
ps_calls() { if [[ -f "$work/ps-calls" ]]; then wc -l < "$work/ps-calls" | tr -d ' '; else echo 0; fi; }

attach_client P "$SSHD -c '$ATTACH'"
wait_clients 1
check "remote-session tmux-any → 2（判不出）" "$(no_ps "$RS" tmux-any >/dev/null 2>&1; echo $?)" 2
check "remote-session tmux-all → 2（判不出）" "$(no_ps "$RS" tmux-all >/dev/null 2>&1; echo $?)" 2
check "remote-session clients 无输出" "$(no_ps "$RS" clients 2>&1)" ""
check "vv-utils tmux_clients → nil" \
  "$(no_ps nvim --headless -u NONE --cmd "set rtp+=$VV" -c "lua io.write(tostring(require('vv-utils.sys.remote').tmux_clients()))" -c 'qa!' 2>&1)" nil
check "有 SSH_TTY：remote-session any" "$(no_ps SSH_TTY=/dev/ttys001 "$RS" any >/dev/null 2>&1; echo $?)" 0
check "有 SSH_TTY：remote-session ps 只调一次" "$(ps_calls)" 1
check "有 SSH_TTY：vv-utils is_remote" "$(no_ps SSH_TTY=/dev/ttys001 bash "$work/lua-is-remote.sh")" remote
# lua-is-remote 同时跑同步与异步两次判定：每次判定 ps 只调一次 → 共 2 次
check "有 SSH_TTY：vv-utils ps 每次判定只调一次（同步 + 异步）" "$(ps_calls)" 2
check "无 SSH 环境变量：remote-session any" "$(no_ps "$RS" any >/dev/null 2>&1; echo $?)" 1
check "无 SSH 环境变量：vv-utils is_remote" "$(no_ps bash "$work/lua-is-remote.sh")" local
detach_all

echo "== 不在 tmux 且 ps 不可用（按环境变量）"
# no_ps_notmux [VAR=val...] <cmd...>：假 ps，且 TMUX 未定义
no_ps_notmux() { rm -f "$work/ps-calls"; env -u TMUX PATH="$work/fakeps:$PATH" "$@"; }
check "有 SSH_TTY：remote-session any" "$(no_ps_notmux SSH_TTY=/dev/ttys001 "$RS" any >/dev/null 2>&1; echo $?)" 0
check "有 SSH_TTY：vv-utils is_remote" "$(no_ps_notmux SSH_TTY=/dev/ttys001 bash "$work/lua-is-remote.sh")" remote
check "SSH_CONNECTION 两端回环：remote-session any" \
  "$(no_ps_notmux SSH_CONNECTION='127.0.0.1 1 127.0.0.1 22' "$RS" any >/dev/null 2>&1; echo $?)" 1
check "SSH_CONNECTION 两端回环：vv-utils is_remote" \
  "$(no_ps_notmux SSH_CONNECTION='127.0.0.1 1 127.0.0.1 22' bash "$work/lua-is-remote.sh")" local
check "无 SSH 环境变量：remote-session any" "$(no_ps_notmux "$RS" any >/dev/null 2>&1; echo $?)" 1
check "无 SSH 环境变量：vv-utils is_remote" "$(no_ps_notmux bash "$work/lua-is-remote.sh")" local

echo "== 不在 tmux：自身进程链（环境变量清空，只有祖先链能暴露远程）"
# self_case <label> <prefix> <want> [tmux env]：tmux env 默认 unset TMUX（不在 tmux）
self_case() {
  local label="$1" prefix="$2" want="$3" tmux_env="${4:-unset TMUX}"
  # unset 而非置空：不在 tmux 时 TMUX 根本未定义（曾因 set -u 下直接读 $TMUX 而报错退出）
  local env="$tmux_env; export SSH_CONNECTION= SSH_TTY= SSH_CLIENT="
  check "${label}：remote-session any" \
    "$(run_clean "$env; $prefix -c '\"\$0\" any >/dev/null 2>&1; echo \$?; :' '$RS'")" "$want"
  check "${label}：vv-utils is_remote" \
    "$(run_clean "$env; $prefix -c 'bash \"\$0\"; :' '$work/lua-is-remote.sh'")" "$([[ $want == 0 ]] && echo remote || echo local)"
}
self_case "在 sshd-session 之下" "$SSHD" 0
self_case "在 mosh-server 之下" "$MOSH" 0
self_case "本地（无远程祖先）" "exec bash" 1
if [[ -n "$SSHD_TITLE" ]]; then
  self_case "在 'sshd-session: es@pts/0' 之下" "$SSHD_TITLE" 0
fi

echo "== 在 tmux 但无 client：退回自身进程链（两边一致）"
check "前提：tmux-any 无 client → 2" "$(TMUX="$T,0,0" rc "$RS" tmux-any)" 2
IN_T="export TMUX='$T,0,0'"
self_case "tmux 内、在 sshd-session 之下" "$SSHD" 0 "$IN_T"
self_case "tmux 内、在 mosh-server 之下" "$MOSH" 0 "$IN_T"
self_case "tmux 内、本地（无远程祖先）" "exec bash" 1 "$IN_T"

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
