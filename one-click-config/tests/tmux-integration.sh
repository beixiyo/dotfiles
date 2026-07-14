#!/usr/bin/env bash
# setup-tmux.sh 行为回归：使用 git、tmux 与 TPM 命令替身，不联网也不接触真实 tmux server

set -u

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_DIR='/tmp/one-click-config-tmux-fixture'
BIN_DIR="$FIXTURE_DIR/bin"
CONFIG_DIR="$FIXTURE_DIR/config"
TMUX_DIR="$CONFIG_DIR/tmux"
CALLS_FILE="$FIXTURE_DIR/calls.log"
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
  rm -rf "$FIXTURE_DIR"
}

trap cleanup EXIT
cleanup
mkdir -p "$BIN_DIR" "$TMUX_DIR"
: > "$CALLS_FILE"

cat > "$BIN_DIR/git" <<'EOF'
#!/usr/bin/env bash
set -eu

printf 'git %s\n' "$*" >> "$CALLS_FILE"

if [ "${1:-}" != 'clone' ]; then
  exit 1
fi

target="${!#}"
mkdir -p "$target/.git" "$target/bin"

cat > "$target/bin/install_plugins" <<'SCRIPT'
#!/usr/bin/env bash
printf 'install args=%s tmux=%s tmpdir=%s plugin_path=%s\n' \
  "$*" "${TMUX-unset}" "${TMUX_TMPDIR-}" "${TMUX_PLUGIN_MANAGER_PATH-}" >> "$CALLS_FILE"
[ -n "${TMUX_TMPDIR-}" ] && [ -d "$TMUX_TMPDIR" ] && [ "${TMUX-unset}" = 'unset' ]
[ "${FAIL_TPM:-0}" != '1' ]
SCRIPT

cat > "$target/bin/update_plugins" <<'SCRIPT'
#!/usr/bin/env bash
printf 'update args=%s tmux=%s tmpdir=%s plugin_path=%s\n' \
  "$*" "${TMUX-unset}" "${TMUX_TMPDIR-}" "${TMUX_PLUGIN_MANAGER_PATH-}" >> "$CALLS_FILE"
[ -n "${TMUX_TMPDIR-}" ] && [ -d "$TMUX_TMPDIR" ] && [ "${TMUX-unset}" = 'unset' ]
[ "${FAIL_TPM:-0}" != '1' ]
SCRIPT

chmod +x "$target/bin/install_plugins" "$target/bin/update_plugins"
EOF
chmod +x "$BIN_DIR/git"

cat > "$BIN_DIR/tmux" <<'EOF'
#!/usr/bin/env bash
printf 'tmux %s\n' "$*" >> "$CALLS_FILE"
EOF
chmod +x "$BIN_DIR/tmux"

run_setup() {
  env \
    HOME="$FIXTURE_DIR/home" \
    XDG_CONFIG_HOME="$CONFIG_DIR" \
    CALLS_FILE="$CALLS_FILE" \
    FAIL_TPM="${FAIL_TPM:-0}" \
    PATH="$BIN_DIR:/usr/local/bin:/usr/bin:/bin" \
    bash "$SOURCE_DIR/setup-tmux.sh" "$@"
}

if run_setup >/tmp/setup-tmux-missing.log 2>&1; then
  fail 'missing tmux config must fail'
else
  pass 'missing tmux config fails before plugin installation'
fi

printf '# test tmux config\n' > "$TMUX_DIR/tmux.conf"

if run_setup >/tmp/setup-tmux-install.log 2>&1 && \
  [ "$(grep -c '^git clone ' "$CALLS_FILE")" -eq 1 ] && \
  [ "$(grep -c '^install ' "$CALLS_FILE")" -eq 1 ] && \
  grep -q '^tmux new-session -d -s tpm_setup$' "$CALLS_FILE" && \
  grep -q '^tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH ' "$CALLS_FILE" && \
  grep -q '^tmux kill-server$' "$CALLS_FILE"; then
  pass 'first install clones TPM and uses an isolated tmux server'
else
  fail 'first TPM installation flow'
fi

if run_setup --install >/tmp/setup-tmux-repeat.log 2>&1 && \
  [ "$(grep -c '^git clone ' "$CALLS_FILE")" -eq 1 ] && \
  [ "$(grep -c '^install ' "$CALLS_FILE")" -eq 2 ]; then
  pass 'repeated install reuses the existing TPM checkout'
else
  fail 'idempotent TPM checkout'
fi

if run_setup --update >/tmp/setup-tmux-update.log 2>&1 && \
  grep -q '^update args=all ' "$CALLS_FILE"; then
  pass 'update mode forwards all to TPM'
else
  fail 'TPM update mode'
fi

if FAIL_TPM=1 run_setup --update >/tmp/setup-tmux-failure.log 2>&1; then
  fail 'TPM failure must propagate'
else
  pass 'TPM failure propagates to the caller'
fi

if run_setup --unknown >/tmp/setup-tmux-unknown.log 2>&1; then
  fail 'unknown argument must fail'
else
  pass 'unknown argument fails explicitly'
fi

printf '%d PASS / %d FAIL\n' "$PASS_COUNT" "$FAIL_COUNT"

[ "$FAIL_COUNT" -eq 0 ]
