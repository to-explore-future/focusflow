#!/bin/bash
set -euo pipefail

NAME="FocusFlow"
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/$NAME.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"

rm -rf "$APP"
mkdir -p "$MACOS" "$RES"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
[ -f "$ROOT/Resources/AppIcon.icns" ]    && cp "$ROOT/Resources/AppIcon.icns"    "$RES/"
[ -f "$ROOT/Resources/MenuBarIcon.png" ] && cp "$ROOT/Resources/MenuBarIcon.png" "$RES/"
[ -f "$ROOT/Resources/MenuBarIcon@2x.png" ] && cp "$ROOT/Resources/MenuBarIcon@2x.png" "$RES/"
[ -f "$ROOT/Resources/DonateQR.png" ] && cp "$ROOT/Resources/DonateQR.png" "$RES/"

swiftc -O \
    -target arm64-apple-macos12.0 \
    -o "$MACOS/$NAME" \
    "$ROOT"/Sources/*.swift \
    -framework Cocoa \
    -framework ApplicationServices

# 用固定的本机证书签名：签名不变，辅助功能授权在重编译后依然有效。
# 没有这个证书时退回 ad-hoc（那样每次重编译都要重新授权）。
IDENTITY="${CODESIGN_IDENTITY:-Wangfou Dev Signing}"
codesign --force --sign "$IDENTITY" --timestamp=none "$APP" 2>/dev/null \
  || codesign --force --sign - --timestamp=none "$APP"

echo "Built: $APP"
echo
echo "Run:    open '$APP'"
echo "Or:     '$MACOS/$NAME'"
echo
echo "First launch will prompt for Accessibility permission."
echo "Grant it in: System Settings > Privacy & Security > Accessibility."
