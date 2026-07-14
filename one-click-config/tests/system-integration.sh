#!/usr/bin/env bash
# Debian 真实系统集成测试，由 tests/run.sh 调用
#
# 在一次性容器中创建真实用户并写入容器自己的 sudoers，验证危险命令过滤、重复写入、
# 非交互式只读检查、当前用户部署属主、sudo 组配置和拒绝 /root 链接后的零副作用
#
# 运行环境由 tests/Dockerfile 提供，项目以只读方式挂载到 /workspace。脚本只修改容器内
# 的 /fixture、/home、/etc/sudoers.d 和 /root，容器退出后全部丢弃

set -euo pipefail

SOURCE_DIR='/workspace'
FIXTURE_ROOT='/fixture'

mkdir -p "$FIXTURE_ROOT"
cp -a "$SOURCE_DIR" "$FIXTURE_ROOT/one-click-config"
mkdir -p "$FIXTURE_ROOT/.config"
printf '# test fixture\n' > "$FIXTURE_ROOT/.zshrc"
printf '# test fixture\n' > "$FIXTURE_ROOT/.config/starship.toml"
git -C "$FIXTURE_ROOT" init -q
git -C "$FIXTURE_ROOT" add -A
git -C "$FIXTURE_ROOT" \
  -c user.name=test \
  -c user.email=test@example.com \
  commit -qm fixture

useradd -m -s /bin/bash tester
chown -R tester:tester "$FIXTURE_ROOT"
printf 'tester ALL=(ALL:ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/tester-bootstrap
chmod 0440 /etc/sudoers.d/tester-bootstrap

cd "$FIXTURE_ROOT"

before_hash="$(sha256sum /etc/sudoers | cut -d' ' -f1)"
bash one-click-config/setup-sudoers.sh --apply vim
after_hash="$(sha256sum /etc/sudoers | cut -d' ' -f1)"
[ "$before_hash" = "$after_hash" ]
[ ! -e /etc/sudoers.d/oneclickconfig-nopasswd ]
printf 'PASS: dangerous --apply command cannot write sudoers\n'

bash one-click-config/setup-sudoers.sh --apply apt pacman >/tmp/apply-first.log
first_hash="$(sha256sum /etc/sudoers.d/oneclickconfig-nopasswd | cut -d' ' -f1)"
bash one-click-config/setup-sudoers.sh --apply apt pacman >/tmp/apply-second.log
second_hash="$(sha256sum /etc/sudoers.d/oneclickconfig-nopasswd | cut -d' ' -f1)"
[ "$first_hash" = "$second_hash" ]
[ "$(grep -o '/usr/bin/apt' /etc/sudoers.d/oneclickconfig-nopasswd | wc -l)" -eq 1 ]
printf 'PASS: repeated sudoers apply is content-idempotent and deduplicated\n'

rm -f /etc/sudoers.d/oneclickconfig-nopasswd
list_output="$(su - tester -c 'timeout 5 bash /fixture/one-click-config/setup-sudoers.sh --list' 2>&1)"
if [[ "$list_output" != *'No NOPASSWD commands configured yet'* ]] && \
  [[ "$list_output" != *'Administrator access is required'* ]]; then
  printf '%s\n' "$list_output" >&2
  exit 1
fi
printf 'PASS: ordinary-user --list returns without an interactive password prompt\n'

printf 'n\nn\nn\nn\n' | \
  su - tester -c 'cd /fixture && bash one-click-config/setup-user.sh' \
    >/tmp/setup-user.log 2>&1

grep -Fq 'Using local repo as source: /fixture' /tmp/setup-user.log
[ -f /home/tester/.zshrc ]
[ "$(stat -c %U /home/tester/.zshrc)" = tester ]
id -nG tester | tr ' ' '\n' | grep -qx sudo
[ ! -L /root/.zshrc ]
printf 'PASS: current-user deploy uses local source and preserves ownership\n'
printf 'PASS: current user receives sudo membership\n'
printf 'PASS: declining root link creates no root link\n'

bash -n one-click-config/setup-*.sh one-click-config/lib/*.sh
printf 'PASS: all setup and library scripts parse in Debian\n'
