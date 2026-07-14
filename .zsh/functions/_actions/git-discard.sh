#!/usr/bin/env bash
file=$1
status=$(git status --porcelain -- "$file" 2>/dev/null)
[[ -z "$status" ]] && exit 0

idx=${status:0:1}
wt=${status:1:1}

if [[ "$wt" == " " && "$idx" != "?" ]]; then
  echo "⚠ 该文件仅有暂存修改，不可丢弃"
  sleep 1
  exit 0
fi

if [[ "$idx" == "?" && "$wt" == "?" ]]; then
  printf '⚠ 确认删除未跟踪文件 %s? (y/N) ' "$file"
else
  printf '⚠ 确认丢弃 %s 的修改? (y/N) ' "$file"
fi

read -r -n 1 confirm
echo
if [[ "$confirm" == [yY] ]]; then
  if [[ "$idx" == "?" && "$wt" == "?" ]]; then
    rm -f -- "$file"
    echo "✓ 已删除"
  else
    git checkout -- "$file"
    echo "✓ 已还原"
  fi
  sleep 0.5
else
  echo "已取消"
  sleep 0.5
fi
