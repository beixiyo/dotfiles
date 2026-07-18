#!/usr/bin/env bash
# 一键安装 NVIDIA 驱动（Arch Linux，幂等）
#
# 用法：
#   sudo ./setup-nvidia.sh
#
# 自动完成：
#   1. 检测 NVIDIA GPU 及架构
#   2. 安装驱动包（nvidia-open / nvidia-open-lts / nvidia-open-dkms）
#   3. 配置 initramfs 早加载
#   4. 验证 DRM modeset
#   5. 创建 Wayland 合成器 VRAM 优化配置
#   6. 混合显卡：安装 nvidia-prime
#
# 不包含（因人而异，需手动配置）：
#   - PRIME 全局分流（niri environment）
#   - 合成器独显渲染（render-drm-device）
#   - Sunshine NVENC 配置

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
for lib_file in common packages; do
  source "$LIB_DIR/${lib_file}.sh"
done

init_colors
require_root

# ─── 1. 检测 NVIDIA GPU ───

log "检测 NVIDIA GPU..."

NVIDIA_PCI=$(lspci -d 10de: -nn 2>/dev/null | grep -E '\[03[0-9]{2}\]' || true)
if [[ -z "$NVIDIA_PCI" ]]; then
  log_err "未检测到 NVIDIA GPU，无需安装驱动"
  exit 1
fi

log "$NVIDIA_PCI"

NVIDIA_DEVICE_ID=$(echo "$NVIDIA_PCI" | head -1 | grep -oP '10de:\K[0-9a-f]{4}' || true)
NVIDIA_TYPE=$(echo "$NVIDIA_PCI" | head -1 | grep -oP '^\S+\s+\K(VGA compatible controller|3D controller)' || true)

HAS_IGPU=$(lspci -d ::0300 2>/dev/null | grep -v "NVIDIA" || true)
IS_HYBRID=false
# 只要同时存在非 NVIDIA 的 0300 显示设备即判为混合显卡。
# 不再要求 NVIDIA_TYPE=="3D controller"：部分游戏本把 dGPU 暴露为 VGA controller，
# 强加该约束会把这类机器误判为独显直连并漏装 nvidia-prime
if [[ -n "$HAS_IGPU" ]]; then
  IS_HYBRID=true
  log "混合显卡（iGPU + NVIDIA dGPU）"
  log "  iGPU: $HAS_IGPU"
else
  log "独立 NVIDIA GPU（台式机 / 独显直连）"
fi

# ─── 2. 选择驱动包 ───

# Turing+ (device ID >= 0x1e00) 用 nvidia-open，Pre-Turing 提示手动装 AUR 包
DRIVER_PKG="nvidia-open"
if [[ -z "$NVIDIA_DEVICE_ID" ]]; then
  log_warn "无法解析 NVIDIA device id，默认使用 $DRIVER_PKG"
else
  DEVICE_NUM=$((16#${NVIDIA_DEVICE_ID}))
  if (( DEVICE_NUM < 0x1e00 )); then
    log_warn "设备 ID 0x${NVIDIA_DEVICE_ID} 可能是 Pre-Turing"
    log_warn "如果 nvidia-open 不工作，请改用 nvidia-580xx-dkms (AUR)"
  fi
fi

# 适配内核变体
if pacman -Qq linux-lts &>/dev/null && ! pacman -Qq linux &>/dev/null; then
  DRIVER_PKG="nvidia-open-lts"
  log "检测到 linux-lts 内核 → $DRIVER_PKG"
elif ! pacman -Qq linux &>/dev/null; then
  DRIVER_PKG="nvidia-open-dkms"
  log "非标准内核 → $DRIVER_PKG (DKMS)"
fi

log "驱动包：$DRIVER_PKG"

# ─── 3. 安装包 ───

PKGS=("linux-headers" "$DRIVER_PKG" "nvidia-utils" "vulkan-tools")

$IS_HYBRID && PKGS+=("nvidia-prime")
echo "$HAS_IGPU" | grep -qi intel && PKGS+=("vulkan-intel")

NEED_INSTALL=()
for pkg in "${PKGS[@]}"; do
  pacman -Qq "$pkg" &>/dev/null || NEED_INSTALL+=("$pkg")
done

if [[ ${#NEED_INSTALL[@]} -gt 0 ]]; then
  log "安装：${NEED_INSTALL[*]}"
  sync_package_manager_once
  pacman -S --needed --noconfirm "${NEED_INSTALL[@]}"
  log_ok "包安装完成"
else
  log_ok "所有包已安装"
fi

# ─── 4. 配置 initramfs ───

MKINIT="/etc/mkinitcpio.conf"
NVIDIA_MODULES="nvidia nvidia_modeset nvidia_uvm nvidia_drm"

if grep -qE "^MODULES=.*nvidia" "$MKINIT"; then
  log_ok "initramfs 已包含 nvidia 模块"
else
  log "配置 initramfs 早加载..."
  cp "$MKINIT" "${MKINIT}.bak.$(date +%s)"

  if grep -qE "^MODULES=\(\)" "$MKINIT"; then
    sed -i "s/^MODULES=()/MODULES=($NVIDIA_MODULES)/" "$MKINIT"
  elif grep -qE "^MODULES=\(" "$MKINIT"; then
    sed -i "s/^MODULES=(\(.*\))/MODULES=(\1 $NVIDIA_MODULES)/" "$MKINIT"
  else
    echo "MODULES=($NVIDIA_MODULES)" >> "$MKINIT"
  fi

  log_ok "MODULES=($NVIDIA_MODULES)"

  log "重建 initramfs..."
  mkinitcpio -P
  log_ok "initramfs 重建完成"
  REBUILT_INITRAMFS=true
fi

# ─── 5. DRM modeset ───

if [[ -f /sys/module/nvidia_drm/parameters/modeset ]]; then
  MODESET=$(cat /sys/module/nvidia_drm/parameters/modeset)
  if [[ "$MODESET" == "Y" ]]; then
    log_ok "DRM modeset 已启用"
  else
    log_warn "DRM modeset 未启用，nvidia-utils ≥ 560 应默认启用"
    log_warn "手动启用：echo 'options nvidia_drm modeset=1' > /etc/modprobe.d/nvidia-drm.conf"
  fi
else
  log "nvidia_drm 模块未加载（需要重启）"
fi

# ─── 6. VRAM 优化 ───

VRAM_DIR="/etc/nvidia/nvidia-application-profiles-rc.d"
VRAM_FILE="$VRAM_DIR/50-wayland-compositor.json"

COMPOSITOR=""
for name in niri sway Hyprland; do
  command -v "$name" &>/dev/null && COMPOSITOR="$name" && break
done

if [[ -n "$COMPOSITOR" ]]; then
  if [[ -f "$VRAM_FILE" ]]; then
    log_ok "VRAM 优化已配置（$COMPOSITOR）"
  else
    log "创建 VRAM 优化配置（$COMPOSITOR）..."
    ensure_dir "$VRAM_DIR"
    cat > "$VRAM_FILE" << EOF
{
    "rules": [
        {
            "pattern": { "feature": "procname", "matches": "$COMPOSITOR" },
            "profile": "Limit free buffer pool on Wayland compositors"
        }
    ],
    "profiles": [
        {
            "name": "Limit free buffer pool on Wayland compositors",
            "settings": [
                { "key": "GLVidHeapReuseRatio", "value": 0 }
            ]
        }
    ]
}
EOF
    log_ok "$VRAM_FILE"
  fi
fi

# ─── 7. 总结 ───

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_ok "NVIDIA 驱动安装完成"
echo ""
echo "  GPU:      $(echo "$NVIDIA_PCI" | head -1 | sed 's/.*: //')"
echo "  驱动:     $DRIVER_PKG"
echo "  混合显卡: $IS_HYBRID"
[[ -n "$COMPOSITOR" ]] && echo "  合成器:   $COMPOSITOR (VRAM 优化已配置)"
echo ""

if [[ "${REBUILT_INITRAMFS:-}" == "true" ]] || ! lsmod | grep -q nvidia; then
  log_warn "需要重启：reboot"
else
  log_ok "驱动已加载，无需重启"
fi

echo ""
echo "  验证：nvidia-smi"
$IS_HYBRID && echo "  混合显卡后续：手动配置 PRIME 分流 / 独显渲染 / Sunshine"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
