#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/Build"
APP_PRODUCT="DynamicIsland"
APP_DISPLAY_NAME="灵动岛"
APP_VERSION="${APP_VERSION:-1.0.2}"
APP_BUILD="${APP_BUILD:-3}"
APPCAST_URL="${APPCAST_URL:-https://raw.githubusercontent.com/weizhiyan/Mac-dynamic-island/main/appcast.xml}"
SPARKLE_PUBLIC_KEY="28WnLNAVZfPjPPkIQIZlni3sSjuwE8kvn3nPAT2X/W8="
APP_BUNDLE="$BUILD_DIR/$APP_DISPLAY_NAME.app"
BUILD_ARCH="${BUILD_ARCH:-}"
SIGNING_ROOT="/tmp/lingdongdao-signing"
SIGNED_APP_BUNDLE="$SIGNING_ROOT/$APP_DISPLAY_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
PLIST_FILE="$CONTENTS_DIR/Info.plist"

cd "$ROOT_DIR"

BUILD_ARCH_FLAGS=()
if [[ -n "$BUILD_ARCH" ]]; then
  BUILD_ARCH_FLAGS=(--arch "$BUILD_ARCH")
fi

swift build -c release --disable-sandbox --product "$APP_PRODUCT" "${BUILD_ARCH_FLAGS[@]}"

BIN_DIR="$(swift build -c release --disable-sandbox --show-bin-path "${BUILD_ARCH_FLAGS[@]}")"
BINARY_PATH="$BIN_DIR/$APP_PRODUCT"
if [[ -z "${BINARY_PATH:-}" ]]; then
  echo "Could not find built binary."
  exit 1
fi
RESOURCE_BUNDLE="$BIN_DIR/${APP_PRODUCT}_${APP_PRODUCT}.bundle"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"
cp "$BINARY_PATH" "$MACOS_DIR/$APP_PRODUCT"
chmod +x "$MACOS_DIR/$APP_PRODUCT"

if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
fi

if [[ -d "$BIN_DIR/Sparkle.framework" ]]; then
  cp -R "$BIN_DIR/Sparkle.framework" "$FRAMEWORKS_DIR/"
  if ! otool -l "$MACOS_DIR/$APP_PRODUCT" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_PRODUCT"
  fi
else
  echo "Could not find Sparkle.framework in $BIN_DIR."
  exit 1
fi

if [[ -f "$ROOT_DIR/Sources/DynamicIsland/Resources/AppIcon.icns" ]]; then
  cp "$ROOT_DIR/Sources/DynamicIsland/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

cat > "$PLIST_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_PRODUCT</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.zhiyan.dynamicisland</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>LSUIElement</key>
  <true/>
  <key>SUFeedURL</key>
  <string>$APPCAST_URL</string>
  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>
</dict>
</plist>
EOF

touch "$APP_BUNDLE"
find "$APP_BUNDLE" \( -name ".DS_Store" -o -name "._*" \) -delete
xattr -cr "$APP_BUNDLE" 2>/dev/null || true
xattr -rd com.apple.FinderInfo "$APP_BUNDLE" 2>/dev/null || true
xattr -rd com.apple.ResourceFork "$APP_BUNDLE" 2>/dev/null || true
xattr -rd 'com.apple.fileprovider.fpfs#P' "$APP_BUNDLE" 2>/dev/null || true
find "$APP_BUNDLE" -exec xattr -d com.apple.FinderInfo {} + 2>/dev/null || true
find "$APP_BUNDLE" -exec xattr -d com.apple.ResourceFork {} + 2>/dev/null || true
find "$APP_BUNDLE" -exec xattr -d 'com.apple.fileprovider.fpfs#P' {} + 2>/dev/null || true
find "$APP_BUNDLE" -xattrname com.apple.FinderInfo -exec xattr -d com.apple.FinderInfo {} \; 2>/dev/null || true
find "$APP_BUNDLE" -xattrname com.apple.ResourceFork -exec xattr -d com.apple.ResourceFork {} \; 2>/dev/null || true
find "$APP_BUNDLE" -xattrname 'com.apple.fileprovider.fpfs#P' -exec xattr -d 'com.apple.fileprovider.fpfs#P' {} \; 2>/dev/null || true

rm -rf "$SIGNING_ROOT"
mkdir -p "$SIGNING_ROOT"
ditto --norsrc --noextattr --noacl --noqtn "$APP_BUNDLE" "$SIGNED_APP_BUNDLE"
# 优先用自签名证书 LingDongDaoDev（签名身份跨构建稳定，TCC 权限授权一次永久有效）；
# 没有则退回 adhoc 签名（每次重建后需在系统设置里重新授权）
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]] && security find-identity -v -p codesigning 2>/dev/null | grep -q "LingDongDaoDev"; then
  SIGN_IDENTITY="LingDongDaoDev"
fi
if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "使用稳定签名身份：$SIGN_IDENTITY"
  codesign --force --sign "$SIGN_IDENTITY" --deep "$SIGNED_APP_BUNDLE" >/dev/null
else
  echo "未找到签名证书，使用 adhoc 签名"
  codesign --force --sign - --deep "$SIGNED_APP_BUNDLE" >/dev/null
fi
rm -rf "$APP_BUNDLE"
ditto --norsrc --noextattr --noacl --noqtn "$SIGNED_APP_BUNDLE" "$APP_BUNDLE"
if [[ "${NO_OPEN:-0}" != "1" ]]; then
  # 先收掉旧进程再开新的：同一个 bundle id 跑两份时，两条收纳分隔符会互相挤，
  # 后启动的那条会被推到屏幕外（实测读到 x=-3805），收纳落点就会算到屏幕外去。
  pkill -f "灵动岛.app/Contents/MacOS/DynamicIsland" 2>/dev/null || true
  sleep 1
  open -n "$APP_BUNDLE"
fi
