#!/usr/bin/env bash
# 在一次性 Arch 容器中调用真实通用安装器与音乐安装入口，验证默认安装和初始化边界
# 包管理器、进程与 systemd 使用替身；不安装音乐包、不启动真实用户服务

set -euo pipefail

SOURCE_DIR='/workspace'
FIXTURE_DIR='/tmp/one-click-config-music-fixture'
DOTFILES_DIR="$FIXTURE_DIR/dotfiles"
INSTALLER_DIR="$DOTFILES_DIR/one-click-config"
BIN_DIR="$FIXTURE_DIR/bin"
STATE_DIR="$FIXTURE_DIR/state"
CALLS_FILE="$FIXTURE_DIR/calls"
OUTPUT_FILE="$FIXTURE_DIR/output"

cleanup() {
  rm -rf "$FIXTURE_DIR"
}
trap cleanup EXIT
cleanup
mkdir -p "$INSTALLER_DIR" "$BIN_DIR" "$STATE_DIR" "$FIXTURE_DIR/home" \
  "$DOTFILES_DIR/.config/mpd" "$DOTFILES_DIR/.config/systemd/user/mpd-mpris.service.d"
cp "$SOURCE_DIR/setup-music.sh" "$INSTALLER_DIR/"
cp -R "$SOURCE_DIR/lib" "$INSTALLER_DIR/"
cp "$SOURCE_DIR/../.config/mpd/mpd.conf" "$DOTFILES_DIR/.config/mpd/"
cp "$SOURCE_DIR/../.config/systemd/user/mpd-mpris.service.d/mpd-socket.conf" \
  "$DOTFILES_DIR/.config/systemd/user/mpd-mpris.service.d/"

export HOME="$FIXTURE_DIR/home"
unset XDG_CONFIG_HOME XDG_STATE_HOME
export PATH="$BIN_DIR:/usr/local/sbin:/usr/local/bin:/usr/bin"
export MUSIC_TEST_STATE="$STATE_DIR" MUSIC_TEST_CALLS="$CALLS_FILE" MUSIC_TEST_BIN="$BIN_DIR"

cat > "$BIN_DIR/pacman" <<'EOF'
#!/usr/bin/env bash
printf 'pacman %s\n' "$*" >> "${MUSIC_TEST_CALLS:?}"
if [ "${1:-}" = '-S' ] && [ "${*: -1}" = "${FAIL_PACKAGE:-}" ]; then
  exit 42
fi
if [ "${1:-}" = '-S' ]; then
  printf '#!/usr/bin/env bash\nexit 0\n' > "${MUSIC_TEST_BIN:?}/${*: -1}"
  chmod +x "${MUSIC_TEST_BIN:?}/${*: -1}"
fi
EOF
cat > "$BIN_DIR/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "${MUSIC_TEST_CALLS:?}"
if [ "${2:-}" = 'is-active' ]; then
  shift 3
  for unit in "$@"; do
    [ ! -e "${MUSIC_TEST_STATE:?}/$unit" ] || exit 0
  done
  exit 3
fi
if [ "${2:-}" = 'enable' ]; then
  [ "${FAIL_START:-0}" != 1 ] || exit 1
  shift 3
  for unit in "$@"; do
    if [ "$unit" = mpd-mpris.service ] && [ "${INACTIVE_BRIDGE:-0}" = 1 ]; then
      continue
    fi
    touch "${MUSIC_TEST_STATE:?}/$unit"
  done
fi
EOF
cat > "$BIN_DIR/pgrep" <<'EOF'
#!/usr/bin/env bash
[ -e "${MUSIC_TEST_STATE:?}/manual-${*: -1}" ]
EOF
cat > "$BIN_DIR/uname" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${TEST_OS:-Linux}"
EOF
chmod +x "$BIN_DIR/"*

# 只把无关通用依赖标记为已安装，音乐命令和包管理器仍按 fixture 的真实 PATH 探测
run_deps() (
  # shellcheck disable=SC2329 # 导出到运行真实安装器的子 Bash，替代其 command -v 探测
  command() {
    if [ "${1:-}" = '-v' ]; then
      case "${2:-}" in
        mpd|rmpc|mpd-mpris|paru|yay|pacman|apt-get|apt|dnf|yum|zypper|brew) ;;
        *) return 0 ;;
      esac
    fi
    builtin command "$@"
  }
  export -f command
  printf '%b' "$1" | bash "$SOURCE_DIR/setup-deps.sh" > "$OUTPUT_FILE" 2>&1
)

# 安装阶段不能创建配置、运行目录或调用服务管理器
assert_no_runtime_setup() {
  [ ! -e "$HOME/.config" ] && [ ! -e "$HOME/Music" ]
  if grep -q '^systemctl ' "$CALLS_FILE"; then
    printf 'FAIL: dependency installation must not manage services\n' >&2
    exit 1
  fi
}

run_music() {
  bash "$INSTALLER_DIR/setup-music.sh" "$@" > "$OUTPUT_FILE" 2>&1
}

: > "$CALLS_FILE"
run_deps 'y\ny\n'
[ ! -s "$CALLS_FILE" ]
assert_no_runtime_setup
printf 'PASS: general setup-deps has no music installation or service side effects\n'

: > "$CALLS_FILE"
run_music --deps-only
for package in mpd rmpc mpd-mpris; do
  grep -Fxq "pacman -S --needed --noconfirm $package" "$CALLS_FILE"
done
assert_no_runtime_setup
printf 'PASS: music dependency mode installs all three Linux commands without runtime setup\n'

: > "$CALLS_FILE"
run_music --deps-only
[ ! -s "$CALLS_FILE" ]
assert_no_runtime_setup
printf 'PASS: installed music commands skip package synchronization and installation\n'

rm -f "$BIN_DIR/mpd" "$BIN_DIR/rmpc" "$BIN_DIR/mpd-mpris"
: > "$CALLS_FILE"
TEST_OS=Darwin run_music --deps-only
grep -Fxq 'pacman -S --needed --noconfirm mpd' "$CALLS_FILE"
grep -Fxq 'pacman -S --needed --noconfirm rmpc' "$CALLS_FILE"
if grep -q 'mpd-mpris' "$CALLS_FILE"; then exit 1; fi
assert_no_runtime_setup
printf 'PASS: non-Linux dependency installation excludes the MPRIS bridge\n'

rm -f "$BIN_DIR/mpd" "$BIN_DIR/rmpc" "$BIN_DIR/mpd-mpris"
: > "$CALLS_FILE"
failure_rc=0
FAIL_PACKAGE=rmpc run_music --deps-only || failure_rc=$?
[ "$failure_rc" -eq 42 ]
assert_no_runtime_setup
printf 'PASS: package installation failure returns nonzero without starting services\n'

run_music --deps-only

assert_no_enable() {
  if grep -q '^systemctl .*enable' "$CALLS_FILE"; then
    printf 'FAIL: skipped initialization must not enable services\n' >&2
    exit 1
  fi
}

: > "$CALLS_FILE"
run_music --mpris
[ ! -e "$HOME/.config" ] && [ ! -e "$HOME/Music" ]
assert_no_enable
printf 'PASS: missing configs are not deployed by the music initializer\n'

mkdir -p "$HOME/.config/mpd"
cp "$DOTFILES_DIR/.config/mpd/mpd.conf" "$HOME/.config/mpd/"
: > "$CALLS_FILE"
run_music
assert_no_enable
[ ! -e "$HOME/.config/systemd" ]
[ ! -d "$HOME/Music" ]
printf 'PASS: default Linux setup requires deployed bridge config and never creates it\n'

cp -R "$DOTFILES_DIR/.config/." "$HOME/.config/"
rm -f "$BIN_DIR/mpd" "$BIN_DIR/rmpc" "$BIN_DIR/mpd-mpris"
: > "$CALLS_FILE"
run_music
for package in mpd rmpc mpd-mpris; do
  grep -Fxq "pacman -S --needed --noconfirm $package" "$CALLS_FILE"
done
grep -Fxq 'systemctl --user enable --now mpd.service mpd-mpris.service' "$CALLS_FILE"
grep -Fxq 'systemctl --user is-active --quiet mpd.service' "$CALLS_FILE"
grep -Fxq 'systemctl --user is-active --quiet mpd-mpris.service' "$CALLS_FILE"
[ -d "$HOME/Music" ] && [ -d "$HOME/.config/mpd/playlists" ] && [ -d "$HOME/.local/state/mpd" ]
printf 'PASS: default setup installs all music commands and initializes both Linux services\n'

: > "$CALLS_FILE"
run_music --mpris
assert_no_enable
printf 'PASS: repeated initialization preserves active services\n'

rm -f "$STATE_DIR/"*.service
for process in mpd mpd-mpris; do
  touch "$STATE_DIR/manual-$process"
  : > "$CALLS_FILE"
  run_music --mpris
  assert_no_enable
  rm -f "$STATE_DIR/manual-$process"
done
printf 'PASS: manual MPD and bridge instances are preserved\n'

for config in mpd/mpd.conf systemd/user/mpd-mpris.service.d/mpd-socket.conf; do
  printf 'custom config\n' > "$HOME/.config/$config"
  : > "$CALLS_FILE"
  run_music --mpris
  assert_no_enable
  grep -Fxq 'custom config' "$HOME/.config/$config"
  cp "$DOTFILES_DIR/.config/$config" "$HOME/.config/$config"
done
printf 'PASS: custom MPD and bridge configs are preserved\n'

: > "$CALLS_FILE"
if FAIL_START=1 run_music --mpris; then
  printf 'FAIL: service start failure must return nonzero\n' >&2
  exit 1
fi
if INACTIVE_BRIDGE=1 run_music --mpris; then
  printf 'FAIL: an inactive bridge must prevent a success result\n' >&2
  exit 1
fi
grep -Fq 'mpd-mpris.service is not active' "$OUTPUT_FILE"
printf 'PASS: start failure and single-service failure cannot report successful initialization\n'

: > "$CALLS_FILE"
TEST_OS=Darwin run_music --mpris
[ ! -s "$CALLS_FILE" ]
printf 'PASS: non-Linux initialization does not invoke systemd\n'
