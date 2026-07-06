#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="1.0.0"
APP_NAME="灵动岛.app"
DMG_NAME="Mac-Dynamic-Island-$VERSION.dmg"
VOLUME_NAME="灵动岛 $VERSION"

cd "$ROOT_DIR"

NO_OPEN=1 "$ROOT_DIR/LaunchDynamicIsland.command"

rm -rf "$ROOT_DIR/Release/dmg-root" "$ROOT_DIR/Release/$DMG_NAME"
mkdir -p "$ROOT_DIR/Release/dmg-root"

cp -R "$ROOT_DIR/Build/$APP_NAME" "$ROOT_DIR/Release/dmg-root/$APP_NAME"
cp "$ROOT_DIR/Scripts/install-local.command" "$ROOT_DIR/Release/dmg-root/安装灵动岛.command"
chmod +x "$ROOT_DIR/Release/dmg-root/安装灵动岛.command"
ln -s /Applications "$ROOT_DIR/Release/dmg-root/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$ROOT_DIR/Release/dmg-root" \
  -ov \
  -format UDZO \
  "$ROOT_DIR/Release/$DMG_NAME"

echo "已生成：$ROOT_DIR/Release/$DMG_NAME"
