#!/usr/bin/env bash
# Niri 安装行为回归，由 tests/run.sh 在一次性 Arch 容器中调用
#
# 使用命令替身运行真实 setup-niri.sh，验证 provider 安装顺序和 locale 安装后的
# 读回契约，不下载完整桌面依赖

set -euo pipefail

SOURCE_DIR='/workspace'
FIXTURE_DIR='/tmp/one-click-config-niri-fixture'
STATE_DIR="$FIXTURE_DIR/state"
BIN_DIR="$FIXTURE_DIR/bin"
PACKAGE_LOG="$FIXTURE_DIR/packages.log"

cleanup() {
  rm -rf "$FIXTURE_DIR"
  rm -f /tmp/niri-deps.out /tmp/niri-locale.out
}

trap cleanup EXIT
cleanup
mkdir -p "$STATE_DIR" "$BIN_DIR"

cat > "$BIN_DIR/pacman" <<'EOF'
#!/usr/bin/env bash
state_dir="${NIRI_TEST_STATE_DIR:?}"
package_log="${NIRI_TEST_PACKAGE_LOG:?}"

case "${1:-}" in
  -Qi)
    [ -e "$state_dir/package-${2:?}" ]
    ;;
  -Syu)
    exit 0
    ;;
  -S)
    package="${*: -1}"
    printf '%s\n' "$package" >> "$package_log"
    touch "$state_dir/package-$package"
    ;;
  *)
    exit 1
    ;;
esac
EOF

cat > "$BIN_DIR/locale" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = '-a' ] && [ -e "${NIRI_TEST_STATE_DIR:?}/package-glibc-locales" ]; then
  printf 'C\nzh_CN.utf8\n'
else
  printf 'C\n'
fi
EOF

chmod +x "$BIN_DIR/pacman" "$BIN_DIR/locale"

export NIRI_TEST_STATE_DIR="$STATE_DIR"
export NIRI_TEST_PACKAGE_LOG="$PACKAGE_LOG"
export PATH="$BIN_DIR:/usr/local/sbin:/usr/local/bin:/usr/bin"

printf 'n\n' | bash "$SOURCE_DIR/setup-niri.sh" --deps >/tmp/niri-deps.out 2>&1

gtk_line="$(grep -nFx 'xdg-desktop-portal-gtk' "$PACKAGE_LOG" | cut -d: -f1)"
jack_line="$(grep -nFx 'pipewire-jack' "$PACKAGE_LOG" | cut -d: -f1)"
niri_line="$(grep -nFx 'niri' "$PACKAGE_LOG" | cut -d: -f1)"
gnome_line="$(grep -nFx 'xdg-desktop-portal-gnome' "$PACKAGE_LOG" | cut -d: -f1)"
qt_backend_line="$(grep -nFx 'qt6-multimedia-ffmpeg' "$PACKAGE_LOG" | cut -d: -f1)"
plasma_line="$(grep -nFx 'plasma-workspace' "$PACKAGE_LOG" | cut -d: -f1)"

[ "$gtk_line" -lt "$niri_line" ]
[ "$jack_line" -lt "$gnome_line" ]
[ "$qt_backend_line" -lt "$plasma_line" ]
printf 'PASS: explicit Portal, JACK and Qt providers are installed before consumers\n'

: > "$PACKAGE_LOG"
bash "$SOURCE_DIR/setup-niri.sh" --locale >/tmp/niri-locale.out 2>&1

grep -Fxq 'glibc-locales' "$PACKAGE_LOG"
PATH="$BIN_DIR:/usr/local/sbin:/usr/local/bin:/usr/bin" locale -a | grep -qx 'zh_CN.utf8'
grep -Fq 'zh_CN.UTF-8 locale installed' /tmp/niri-locale.out
printf 'PASS: missing zh_CN locale installs glibc-locales and verifies the result\n'
