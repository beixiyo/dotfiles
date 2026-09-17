#!/bin/sh
# 一键测试：递归跑 tests/**/test_*.lua，每文件独立 nvim -l 子进程，汇总退出码
# 用法：tests/run.sh [过滤词]   过滤词匹配测试文件路径子串
# 与 cwd 无关（按脚本自身路径定位 run.lua），幂等可重复跑
set -eu

exec nvim -l "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/run.lua" "$@"
