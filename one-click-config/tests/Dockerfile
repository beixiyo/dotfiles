# tests/system-integration.sh 的可缓存 Debian 运行环境
# 只安装真实权限与用户集成测试需要的最小系统工具
FROM debian:bookworm-slim

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    git \
    sudo \
    zsh \
  && rm -rf /var/lib/apt/lists/*
