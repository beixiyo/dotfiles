#!/usr/bin/env bash
# 快速权限边界回归，由 tests/run.sh 在 Bash 4.3 容器中调用
#
# 使用临时命令替身验证包管理器提权/降权、危险 sudoers 命令过滤、只读状态判断和
# root 目标选择，不安装软件，也不依赖真实 systemd 或发行版用户管理工具
#
# 通常不需要单独运行；调试时可在兼容的 root 容器中执行：
#   bash /workspace/tests/integration.sh
#
# 所有临时文件都位于 /tmp，并在退出时清理

set -u

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_DIR='/tmp/one-click-config-fixture'
PASS_COUNT=0
FAIL_COUNT=0

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf 'FAIL: %s\n' "$1"
}

cleanup() {
  rm -rf "$FIXTURE_DIR" /tmp/apt-result /tmp/brew-result /tmp/root-brew.out /tmp/setup-deps.out
}

trap cleanup EXIT
cleanup
mkdir -p "$FIXTURE_DIR/bin"

cat > "$FIXTURE_DIR/bin/brew" <<'EOF'
#!/usr/bin/env bash
printf 'uid=%s home=%s args=%s\n' "$(id -u)" "$HOME" "$*" > /tmp/brew-result
EOF
chmod +x "$FIXTURE_DIR/bin/brew"

cat > "$FIXTURE_DIR/bin/apt-get" <<'EOF'
#!/usr/bin/env bash
printf 'uid=%s args=%s\n' "$(id -u)" "$*" > /tmp/apt-result
EOF
chmod +x "$FIXTURE_DIR/bin/apt-get"

cat > "$FIXTURE_DIR/bin/git" <<'EOF'
#!/usr/bin/env bash
printf '/workspace\n'
EOF
chmod +x "$FIXTURE_DIR/bin/git"

cat > "$FIXTURE_DIR/bin/zsh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$FIXTURE_DIR/bin/zsh"
cat > "$FIXTURE_DIR/bin/sudo" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = '-n' ]; then
  shift
fi
if [ "${1:-}" = '--' ]; then
  shift
fi
if [ "${1:-}" = 'cat' ]; then
  exit 1
fi
if [ "${1:-}" = 'test' ] && [ "${2:-}" = '!' ] && [ "${3:-}" = '-e' ]; then
  exit 0
fi
exit 1
EOF
chmod +x "$FIXTURE_DIR/bin/sudo"
ln -s zsh "$FIXTURE_DIR/bin/starship"
ln -s zsh "$FIXTURE_DIR/bin/vim"
ln -s vim "$FIXTURE_DIR/bin/safe-name"

mkdir -p "$FIXTURE_DIR/all-installed"
while IFS= read -r cmd; do
  ln -sf "$FIXTURE_DIR/bin/zsh" "$FIXTURE_DIR/all-installed/$cmd"
done < <(
  sed -n '/^PACKAGES=(/,/^)/p' "$SOURCE_DIR/setup-deps.sh" \
    | sed -n "s/^[[:space:]]*'\([^|]*\).*/\1/p"
)
ln -sf "$FIXTURE_DIR/bin/brew" "$FIXTURE_DIR/all-installed/brew"

rm -f /tmp/brew-result
if PATH="$FIXTURE_DIR/all-installed:$FIXTURE_DIR/bin:/usr/local/bin:/usr/bin:/bin" \
  bash "$SOURCE_DIR/setup-deps.sh" >/tmp/setup-deps.out 2>&1 && \
  [ ! -e /tmp/brew-result ]; then
  pass 'setup-deps skips package-manager sync when every command exists'
else
  sed 's/^/  /' /tmp/setup-deps.out
  fail 'setup-deps no-op package-manager boundary'
fi

# shellcheck disable=SC1091 # 测试固定挂载路径下的真实库文件
source "$SOURCE_DIR/lib/common.sh"
# shellcheck disable=SC1091
source "$SOURCE_DIR/lib/packages.sh"
# shellcheck disable=SC1091
source "$SOURCE_DIR/lib/sudoers.sh"
init_colors

if _is_sudoers_command_denied "$FIXTURE_DIR/bin/vim" && \
  _is_sudoers_command_denied "$FIXTURE_DIR/bin/safe-name" && \
  ! _is_sudoers_command_denied /usr/bin/curl; then
  pass 'dangerous command paths and symlink aliases are rejected'
else
  fail 'dangerous command path filtering'
fi

apply_output="$("$SOURCE_DIR/setup-sudoers.sh" --apply "$FIXTURE_DIR/bin/safe-name" 2>&1)"
if [[ "$apply_output" == *'Skipped'* ]] && [ ! -e /etc/sudoers.d/oneclickconfig-nopasswd ]; then
  pass 'privileged apply mode cannot bypass dangerous command filtering'
else
  fail 'privileged apply dangerous command filtering'
fi

adduser -D package-user
PATH="$FIXTURE_DIR/bin:$PATH"
# shellcheck disable=SC2034 # 由动态 source 的 lib/packages.sh 读取
PKG_MANAGER='brew'
SUDO_USER='package-user'
export SUDO_USER
rm -f /tmp/brew-result
if run_package_command brew install jq && grep -q '^uid=[1-9][0-9]* home=/home/package-user args=install jq$' /tmp/brew-result; then
  unset SUDO_USER
  PKG_MANAGER='apt-get'
  run_package_command apt-get update
fi
if grep -q '^uid=[1-9][0-9]* home=/home/package-user args=install jq$' /tmp/brew-result && \
  grep -q '^uid=0 args=update$' /tmp/apt-result; then
  pass 'user and system package managers use the correct privilege boundary'
else
  fail 'package manager privilege boundary'
fi

# shellcheck disable=SC2034 # 由动态 source 的 lib/packages.sh 读取
PKG_MANAGER='brew'
if (unset SUDO_USER; run_package_command brew install jq) >/tmp/root-brew.out 2>&1; then
  fail 'direct root brew invocation must fail'
else
  pass 'direct root brew invocation fails explicitly'
fi

list_output="$(su package-user -c "$SOURCE_DIR/setup-sudoers.sh --list" 2>&1)"
mkdir -p /etc/sudoers.d
chmod 0750 /etc/sudoers.d
cached_list_output="$(su package-user -c "PATH=$FIXTURE_DIR/bin:$PATH $SOURCE_DIR/setup-sudoers.sh --list" 2>&1)"
if [[ "$list_output" == *'No NOPASSWD commands configured yet'* ]] && \
  [[ "$cached_list_output" == *'No NOPASSWD commands configured yet'* ]]; then
  pass 'missing sudoers drop-in is distinguished from insufficient access'
else
  fail 'missing sudoers drop-in status'
fi

root_output="$(printf 'n\n' | env -u SUDO_USER PATH="$FIXTURE_DIR/bin:$PATH" DOTFILES_LINK_ROOT=no "$SOURCE_DIR/setup-user.sh" 2>&1)"
root_link_output="$(printf 'n\n' | env -u SUDO_USER PATH="$FIXTURE_DIR/bin:$PATH" DOTFILES_LINK_ROOT=yes "$SOURCE_DIR/setup-user.sh" 2>&1)"
empty_users_rc=0
empty_users_output="$(printf 'y\n\n' | env -u SUDO_USER PATH="$FIXTURE_DIR/bin:$PATH" DOTFILES_LINK_ROOT=no "$SOURCE_DIR/setup-user.sh" 2>&1)" || empty_users_rc=$?
if [[ "$root_output" == *'No non-root target user selected; nothing to deploy'* ]] && \
  [[ "$root_link_output" == *'No non-root target user selected; nothing to deploy'* ]] && \
  [[ "$root_output" != *'Deploy dotfiles to current user: root'* ]] && \
  [[ "$root_link_output" != *'Linking config into /root'* ]] && \
  [ "$empty_users_rc" -eq 0 ] && \
  [[ "$empty_users_output" != *'Deploy dotfiles to current user: root'* ]]; then
  pass 'empty user arrays are safe and root is not treated as a deployment target'
else
  fail 'root target selection'
fi

printf '%d PASS / %d FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"

[ "$FAIL_COUNT" -eq 0 ]
