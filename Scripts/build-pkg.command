#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-1.0.5}"
BUILD_ARCH="${BUILD_ARCH:-}"
if [[ -z "${ARTIFACT_SUFFIX:-}" && "$BUILD_ARCH" == "x86_64" ]]; then
  ARTIFACT_SUFFIX="-intel"
else
  ARTIFACT_SUFFIX="${ARTIFACT_SUFFIX:-}"
fi
APP_NAME="灵动岛.app"
PKG_NAME="Mac-Dynamic-Island-$VERSION$ARTIFACT_SUFFIX.pkg"
PKG_ROOT="/tmp/lingdongdao-pkg-root"
PKG_SCRIPTS="$ROOT_DIR/Scripts/pkg-scripts"

cd "$ROOT_DIR"

APP_VERSION="$VERSION" BUILD_ARCH="$BUILD_ARCH" NO_OPEN=1 "$ROOT_DIR/LaunchDynamicIsland.command"

rm -rf "$PKG_ROOT" "$ROOT_DIR/Release/$PKG_NAME"
mkdir -p "$PKG_ROOT/Applications" "$ROOT_DIR/Release"

ditto --norsrc --noextattr --noacl --noqtn "$ROOT_DIR/Build/$APP_NAME" "$PKG_ROOT/Applications/$APP_NAME"

pkgbuild \
  --root "$PKG_ROOT" \
  --scripts "$PKG_SCRIPTS" \
  --identifier com.zhiyan.dynamicisland.pkg \
  --version "$VERSION" \
  --install-location / \
  "$ROOT_DIR/Release/$PKG_NAME"

echo "已生成：$ROOT_DIR/Release/$PKG_NAME"
