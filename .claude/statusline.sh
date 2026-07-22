#!/usr/bin/env bash
# Claude Code 状态栏入口
#
# 优先走全局安装的稳定路径。原因：bunx 会把包解压到 /var/folders/<...>/T/ 再执行，
# 该目录被 Gatekeeper 视为不可信位置，扫描结论永不缓存——每次刷新都要让 XProtect
# 重新编译 971 KB 的 YARA 规则再扫 3 MB 的 JS（单次约 120ms）
# 实测 refreshInterval 为 3 时 XprotectService 常驻 9.5% 单核，改走稳定路径后首次扫 1 次、之后恒为 0
#
# 未安装时自动全局安装一次，保证 clone 下来就能用
#
# 只判断文件是否存在，不比对版本：热路径每次刷新都会走，多一次 fork 就多一份开销
# 因此改 PKG 的版本号不会自动升级，需要手动跑一次：
#   bun add -g ccstatusline-zh@<新版本>
set -euo pipefail

readonly PKG='ccstatusline-zh@2.2.23'

# 全局 bin 目录，等价于 `bun pm bin -g`，但用纯展开算出来，避免热路径多一次 fork
# 优先级抄自 bun 源码的 open_global_bin_dir：
#   BUN_INSTALL_BIN > bunfig 的 install.globalBinDir > $BUN_INSTALL/bin > ${XDG_CACHE_HOME:-$HOME}/.bun/bin
# 唯独 bunfig 那一级要解析 TOML，这里不覆盖；真设了它就把下面换成 `bun pm bin -g` 的实测值
if [[ -n ${BUN_INSTALL_BIN:-} ]]; then
  bun_bin_dir=$BUN_INSTALL_BIN
elif [[ -n ${BUN_INSTALL:-} ]]; then
  bun_bin_dir=$BUN_INSTALL/bin
else
  bun_bin_dir=${XDG_CACHE_HOME:-$HOME}/.bun/bin
fi

readonly BIN="$bun_bin_dir/ccstatusline-zh"

# 安装日志走 stderr，否则会被 Claude Code 当成状态栏内容渲染出来
if [[ ! -x $BIN ]]; then
  bun add -g "$PKG" >&2
fi

exec "$BIN"

