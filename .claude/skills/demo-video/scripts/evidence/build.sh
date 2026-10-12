#!/bin/sh
# 把 lib.js 和场景主体拼成 playwright-cli run-code 能执行的单个函数
# 产物目录下会用到 videos/、shots/；场景主体里用 OUT 引用它
set -e
[ $# -eq 3 ] || { echo "usage: build.sh <scene.body.js> <out.js> <out_dir>" >&2; exit 1; }
out_dir=$(cd "$3" && pwd)
mkdir -p "$out_dir/videos" "$out_dir/shots"
{
  echo "async page => {"
  printf "const OUT = '%s'\n" "$out_dir"
  cat "$(dirname "$0")/lib.js"
  cat "$1"
  echo "}"
} > "$2"
