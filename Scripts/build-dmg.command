#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-1.0.1}"
BUILD_ARCH="${BUILD_ARCH:-}"
if [[ -z "${ARTIFACT_SUFFIX:-}" && "$BUILD_ARCH" == "x86_64" ]]; then
  ARTIFACT_SUFFIX="-intel"
else
  ARTIFACT_SUFFIX="${ARTIFACT_SUFFIX:-}"
fi
APP_NAME="灵动岛.app"
DMG_NAME="Mac-Dynamic-Island-$VERSION$ARTIFACT_SUFFIX.dmg"
VOLUME_NAME="灵动岛 $VERSION"
DMG_ROOT="/tmp/lingdongdao-dmg-root"

cd "$ROOT_DIR"

APP_VERSION="$VERSION" APP_BUILD="${APP_BUILD:-2}" BUILD_ARCH="$BUILD_ARCH" NO_OPEN=1 "$ROOT_DIR/LaunchDynamicIsland.command"

rm -rf "$DMG_ROOT" "$ROOT_DIR/Release/$DMG_NAME"
mkdir -p "$DMG_ROOT" "$ROOT_DIR/Release"

ditto --norsrc --noextattr --noacl --noqtn "$ROOT_DIR/Build/$APP_NAME" "$DMG_ROOT/$APP_NAME"
cp "$ROOT_DIR/Scripts/install-local.command" "$DMG_ROOT/安装灵动岛.command"
chmod +x "$DMG_ROOT/安装灵动岛.command"
ln -s /Applications "$DMG_ROOT/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$ROOT_DIR/Release/$DMG_NAME"

echo "已生成：$ROOT_DIR/Release/$DMG_NAME"
