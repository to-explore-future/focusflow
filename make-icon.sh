#!/bin/bash
# 把一张 1024x1024 的 PNG 转成 AppIcon.icns
# 用法：./make-icon.sh 图标.png
set -euo pipefail
SRC="${1:?用法: ./make-icon.sh 图标.png}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
ICONSET="$ROOT/build/AppIcon.iconset"

rm -rf "$ICONSET"; mkdir -p "$ICONSET" "$ROOT/Resources"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" "$SRC" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$SRC" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
echo "已生成 Resources/AppIcon.icns"
