#!/usr/bin/env zsh
# 用法: zsh ~/.zsh/bench.zsh [runs]
# 测量 zsh 启动时间并输出 zprof 分析

RUNS=${1:-7}
RED='\033[0;31m'; YEL='\033[0;33m'; GRN='\033[0;32m'; CYN='\033[0;36m'; RST='\033[0m'

# ── 1. 总启动时间（多次取样）────────────────────────────
echo "${CYN}── 启动时间 (${RUNS} 次)${RST}"
times=()
for i in $(seq 1 $RUNS); do
  s=$(date +%s%N)
  zsh -i -c exit 2>/dev/null
  e=$(date +%s%N)
  ms=$(( (e - s) / 1000000 ))
  times+=($ms)
  printf "  run %d: %dms\n" $i $ms
done

# 排序取中位数/min/max
sorted=($(printf '%s\n' "${times[@]}" | sort -n))
min=${sorted[1]}
max=${sorted[-1]}
mid=${sorted[$(( ${#sorted} / 2 + 1 ))]}
total=0; for t in "${times[@]}"; do (( total += t )); done
avg=$(( total / ${#times} ))

echo ""
printf "  min: ${GRN}%dms${RST}  median: %dms  avg: %dms  max: ${RED}%dms${RST}\n" \
  $min $mid $avg $max

# ── 2. 评级 ─────────────────────────────────────────────
echo ""
if   (( avg < 100 )); then echo "  ${GRN}★ 优秀 (<100ms)${RST}"
elif (( avg < 200 )); then echo "  ${GRN}✓ 良好 (<200ms)${RST}"
elif (( avg < 400 )); then echo "  ${YEL}△ 尚可 (<400ms)${RST}"
else                       echo "  ${RED}✗ 过慢 (≥400ms)${RST}，建议优化"
fi

# ── 3. 逐段耗时 ─────────────────────────────────────────
echo ""
echo "${CYN}── 逐段耗时${RST}"

_bench_section() {
  local label=$1 cmd=$2
  local s=$(date +%s%N)
  eval "$cmd" 2>/dev/null
  local e=$(date +%s%N)
  local ms=$(( (e - s) / 1000000 ))
  local bar=$(printf '█%.0s' $(seq 1 $(( ms / 5 + 1 ))))
  printf "  %-20s %3dms  ${CYN}%s${RST}\n" "$label" $ms "$bar"
}

# 用子 shell 避免污染当前环境
zsh 2>/dev/null << 'BENCH_SECTIONS'
_t() { date +%s%N; }
_s() { local s=$(_t); eval "$2" 2>/dev/null; local e=$(_t); printf "  %-20s %3dms\n" "$1" $(( (e-s)/1000000 )); }

_s "env.zsh"           "source ~/.zsh/env.zsh"
_s "history.zsh"       "source ~/.zsh/history.zsh"
_s "completions.zsh"   "source ~/.zsh/completions.zsh"
_s "plugins.zsh"       "source ~/.zsh/plugins.zsh"
_s "init.zsh"          "source ~/.zsh/init.zsh"
_s "aliases.zsh"       "source ~/.zsh/aliases.zsh"
_s "functions/"        "source ~/.zsh/functions/index.zsh"
_s "keybindings.zsh"   "source ~/.zsh/keybindings.zsh"
_s "notify.zsh"        "source ~/.zsh/notify.zsh"
BENCH_SECTIONS

# ── 4. zprof Top 10 ─────────────────────────────────────
echo ""
echo "${CYN}── zprof Top 10（单次）${RST}"
zsh 2>/dev/null << 'ZPROF_RUN'
zmodload zsh/zprof
source ~/.zsh/env.zsh
source ~/.zsh/history.zsh
source ~/.zsh/completions.zsh
source ~/.zsh/plugins.zsh
source ~/.zsh/init.zsh
source ~/.zsh/aliases.zsh
source ~/.zsh/functions/index.zsh
source ~/.zsh/keybindings.zsh
source ~/.zsh/notify.zsh
zprof 2>/dev/null | head -15
ZPROF_RUN

# ── 5. eval 子进程耗时 ──────────────────────────────────
echo ""
echo "${CYN}── eval 子进程生成耗时${RST}"
for tool_cmd in "starship|starship init zsh" "mise|mise activate zsh" "zoxide|zoxide init --cmd cd zsh" "fzf|fzf --zsh"; do
  tool=${tool_cmd%%|*}
  cmd=${tool_cmd##*|}
  if command -v $tool &>/dev/null; then
    s=$(date +%s%N)
    eval "$cmd" > /dev/null 2>&1
    e=$(date +%s%N)
    printf "  %-12s %3dms\n" "$tool" $(( (e-s)/1000000 ))
  fi
done
