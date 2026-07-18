#!/usr/bin/env zsh
# 用法: zsh ~/.zsh/bench.zsh [runs]
# 测量 zsh 启动时间并输出 zprof 分析

RUNS=${1:-7}
RED='\033[0;31m'; YEL='\033[0;33m'; GRN='\033[0;32m'; CYN='\033[0;36m'; RST='\033[0m'
zmodload zsh/datetime

# ── 1. 总启动时间（多次取样）────────────────────────────
echo "${CYN}── 启动时间 (${RUNS} 次)${RST}"
times=()
for i in $(seq 1 $RUNS); do
  s=$EPOCHREALTIME
  zsh -i -c exit 2>/dev/null
  printf -v ms '%.0f' $(( (EPOCHREALTIME - s) * 1000 ))
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

# 用子 shell 避免污染当前环境
zsh 2>/dev/null << 'BENCH_SECTIONS'
zmodload zsh/datetime
_s() {
  local label=$1 command=$2
  local start=$EPOCHREALTIME elapsed_ms
  eval "$command" 2>/dev/null
  printf -v elapsed_ms '%.0f' $(( (EPOCHREALTIME - start) * 1000 ))
  printf "  %-20s %3dms\n" "$label" $elapsed_ms
}

_s "env.zsh"           "source ~/.zsh/env.zsh"
_s "options.zsh"       "source ~/.zsh/options.zsh"
_s "plugins.zsh"       "source ~/.zsh/plugins.zsh"
_s "completions.zsh"   "source ~/.zsh/completions.zsh"
_s "tools.zsh"         "source ~/.zsh/tools.zsh"
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
source ~/.zsh/options.zsh
source ~/.zsh/plugins.zsh
source ~/.zsh/completions.zsh
source ~/.zsh/tools.zsh
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
    s=$EPOCHREALTIME
    eval "$cmd" > /dev/null 2>&1
    printf -v ms '%.0f' $(( (EPOCHREALTIME - s) * 1000 ))
    printf "  %-12s %3dms\n" "$tool" $ms
  fi
done
