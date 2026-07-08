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
PKG_NAME="Mac-Dynamic-Island-$VERSION$ARTIFACT_SUFFIX.pkg"
PKG_ROOT="/tmp/lingdongdao-pkg-root"

cd "$ROOT_DIR"

EXPECTED_ARCH="${BUILD_ARCH:-$(uname -m)}"
APP_BINARY="$ROOT_DIR/Build/$APP_NAME/Contents/MacOS/DynamicIsland"
if [[ ! -d "$ROOT_DIR/Build/$APP_NAME" ]] || ! lipo -archs "$APP_BINARY" 2>/dev/null | tr ' ' '\n' | grep -qx "$EXPECTED_ARCH"; then
  APP_VERSION="$VERSION" BUILD_ARCH="$BUILD_ARCH" NO_OPEN=1 "$ROOT_DIR/LaunchDynamicIsland.command"
fi

rm -rf "$PKG_ROOT" "$ROOT_DIR/Release/$PKG_NAME"
mkdir -p "$PKG_ROOT/Applications" "$ROOT_DIR/Release"

ditto --norsrc --noextattr --noacl --noqtn "$ROOT_DIR/Build/$APP_NAME" "$PKG_ROOT/Applications/$APP_NAME"

pkgbuild \
  --root "$PKG_ROOT" \
  --identifier com.zhiyan.dynamicisland.pkg \
  --version "$VERSION" \
  --install-location / \
  "$ROOT_DIR/Release/$PKG_NAME"

echo "已生成：$ROOT_DIR/Release/$PKG_NAME"
