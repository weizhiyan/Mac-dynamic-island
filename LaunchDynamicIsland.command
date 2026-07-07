#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/Build"
APP_PRODUCT="DynamicIsland"
APP_DISPLAY_NAME="灵动岛"
APP_VERSION="${APP_VERSION:-1.0.1}"
APP_BUILD="${APP_BUILD:-2}"
APPCAST_URL="${APPCAST_URL:-https://raw.githubusercontent.com/weizhiyan/Mac-dynamic-island/main/appcast.xml}"
SPARKLE_PUBLIC_KEY="28WnLNAVZfPjPPkIQIZlni3sSjuwE8kvn3nPAT2X/W8="
APP_BUNDLE="$BUILD_DIR/$APP_DISPLAY_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
PLIST_FILE="$CONTENTS_DIR/Info.plist"

cd "$ROOT_DIR"

swift build -c release --product "$APP_PRODUCT"

BIN_DIR="$(swift build -c release --show-bin-path)"
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
find "$APP_BUNDLE" -exec xattr -c {} \; 2>/dev/null || true
codesign --force --sign - --deep "$APP_BUNDLE" >/dev/null
if [[ "${NO_OPEN:-0}" != "1" ]]; then
  open -n "$APP_BUNDLE"
fi
