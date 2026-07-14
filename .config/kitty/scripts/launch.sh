#!/usr/bin/env bash
# 跨平台启动目录检测：Mac → ~/Documents/code/frontend，Linux/WSL → ~/code/frontend
case "$(uname)" in
  Darwin) cd "$HOME/Documents/code/frontend" ;;
  Linux)  cd "$HOME/code/frontend" ;;
esac
exec "${SHELL:-zsh}" -l
