#!/usr/bin/env bash
# one-click-config 测试套件的唯一公开入口
#
# 用法：
#   bash one-click-config/tests/run.sh
#
# 依次执行：
#   1. 使用宿主机 Bash 做语法检查
#   2. 在 ShellCheck 官方容器中做静态检查
#   3. 在缓存的 Debian 测试镜像中验证真实用户、sudoers、属主和 /root 边界
#   4. 在 Bash 4.3 容器中运行快速权限边界与 tmux 安装回归
#
# 前提：Docker CLI 与 daemon 可用。项目目录只读挂载到容器，测试不会修改宿主机的
# 用户、/etc/sudoers 或 /root；Docker 会保留本地测试镜像以加速后续执行

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$TEST_DIR")"

SHELL_FILES=(
  "$PROJECT_DIR/setup-user.sh"
  "$PROJECT_DIR/setup-deps.sh"
  "$PROJECT_DIR/setup-tmux.sh"
  "$PROJECT_DIR/setup-sudoers.sh"
  "$PROJECT_DIR/lib/common.sh"
  "$PROJECT_DIR/lib/packages.sh"
  "$PROJECT_DIR/lib/sudoers.sh"
  "$PROJECT_DIR/lib/repos.sh"
  "$PROJECT_DIR/lib/download.sh"
  "$TEST_DIR/run.sh"
  "$TEST_DIR/integration.sh"
  "$TEST_DIR/system-integration.sh"
  "$TEST_DIR/tmux-integration.sh"
)

if ! command -v docker >/dev/null 2>&1; then
  printf 'docker is required to run one-click-config tests\n' >&2
  exit 1
fi

printf '%s\n' '==> bash -n'
bash -n "${SHELL_FILES[@]}"

printf '%s\n' '==> shellcheck'
docker run --rm \
  -v "$PROJECT_DIR:/workspace:ro" \
  koalaman/shellcheck:stable \
  -x \
  /workspace/setup-user.sh \
  /workspace/setup-deps.sh \
  /workspace/setup-tmux.sh \
  /workspace/setup-sudoers.sh \
  /workspace/lib/common.sh \
  /workspace/lib/packages.sh \
  /workspace/lib/sudoers.sh \
  /workspace/lib/repos.sh \
  /workspace/lib/download.sh \
  /workspace/tests/run.sh \
  /workspace/tests/integration.sh \
  /workspace/tests/system-integration.sh \
  /workspace/tests/tmux-integration.sh

printf '%s\n' '==> Debian system integration tests'
docker build --quiet \
  --file "$TEST_DIR/Dockerfile" \
  --tag one-click-config-tests:local \
  "$TEST_DIR" >/dev/null
docker run --rm \
  -v "$PROJECT_DIR:/workspace:ro" \
  one-click-config-tests:local \
  bash /workspace/tests/system-integration.sh

printf '%s\n' '==> privilege boundary integration tests'
docker run --rm \
  -v "$PROJECT_DIR:/workspace:ro" \
  bash:4.3 \
  bash /workspace/tests/integration.sh

printf '%s\n' '==> tmux plugin installation tests'
docker run --rm \
  -v "$PROJECT_DIR:/workspace:ro" \
  bash:4.3 \
  bash /workspace/tests/tmux-integration.sh
