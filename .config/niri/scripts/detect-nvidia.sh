#!/bin/sh
# 检测 NVIDIA 驱动是否可用，自动生成/删除 nvidia.kdl
TARGET="$HOME/.config/niri/nvidia.kdl"

if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
  # 找 NVIDIA 的 render node（vendor 0x10de）
  RENDER_PATH=""
  for p in /dev/dri/by-path/*-render; do
    card=$(echo "$p" | sed 's/-render$/-card/')
    real_card=$(readlink -f "$card" 2>/dev/null)
    vendor=$(cat "$(dirname "$real_card")/device/vendor" 2>/dev/null)
    if [ "$vendor" = "0x10de" ]; then
      RENDER_PATH=$(readlink -f "$p")
      break
    fi
  done

  cat > "$TARGET" << EOF
environment {
  __NV_PRIME_RENDER_OFFLOAD "1"
  __GLX_VENDOR_LIBRARY_NAME "nvidia"
}

debug {
  render-drm-device "${RENDER_PATH:-/dev/dri/renderD128}"
}
EOF
else
  rm -f "$TARGET"
fi
