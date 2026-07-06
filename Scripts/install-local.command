#!/bin/zsh
set -euo pipefail

APP_NAME="灵动岛.app"
LEGACY_APP_NAME="DynamicIsland.app"
BUNDLE_ID="com.zhiyan.dynamicisland"
INSTALL_DIR="/Applications"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -d "$SOURCE_DIR/$APP_NAME" ]]; then
  SOURCE_APP="$SOURCE_DIR/$APP_NAME"
elif [[ -d "$SOURCE_DIR/../Build/$APP_NAME" ]]; then
  SOURCE_APP="$SOURCE_DIR/../Build/$APP_NAME"
else
  echo "没有找到 $APP_NAME。请从 DMG 内运行此安装脚本。"
  exit 1
fi

echo "正在退出旧版本..."
/usr/bin/pkill -x DynamicIsland 2>/dev/null || true
/bin/sleep 0.5

echo "正在清理旧安装..."
/bin/rm -rf "$INSTALL_DIR/$APP_NAME" "$INSTALL_DIR/$LEGACY_APP_NAME"

while IFS= read -r existingApp; do
  case "$existingApp" in
    "$SOURCE_APP"|"$SOURCE_DIR"/*|/Volumes/*)
      ;;
    "$INSTALL_DIR"/*)
      echo "移除重复副本：$existingApp"
      /bin/rm -rf "$existingApp"
      ;;
  esac
done < <(/usr/bin/mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null || true)

echo "正在安装到 $INSTALL_DIR..."
/bin/cp -R "$SOURCE_APP" "$INSTALL_DIR/$APP_NAME"
/usr/bin/xattr -dr com.apple.quarantine "$INSTALL_DIR/$APP_NAME" 2>/dev/null || true

echo "安装完成：$INSTALL_DIR/$APP_NAME"
/usr/bin/open "$INSTALL_DIR/$APP_NAME"
