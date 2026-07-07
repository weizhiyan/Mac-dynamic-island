#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-1.0.1}"
REPO="${REPO:-weizhiyan/Mac-dynamic-island}"
DMG="$ROOT_DIR/Release/Mac-Dynamic-Island-$VERSION.dmg"
NOTES="$ROOT_DIR/Docs/releases/v$VERSION.md"
ARCHIVES_DIR="$ROOT_DIR/Release/appcast-archives"
APPCAST="$ROOT_DIR/appcast.xml"
DOWNLOAD_PREFIX="${DOWNLOAD_PREFIX:-https://github.com/$REPO/releases/download/v$VERSION/}"

cd "$ROOT_DIR"

if [[ ! -f "$DMG" ]]; then
  echo "Missing $DMG. Building it now..."
  VERSION="$VERSION" ./Scripts/build-dmg.command
fi

if [[ ! -f "$NOTES" ]]; then
  echo "Missing release notes: $NOTES"
  exit 1
fi

GENERATE_APPCAST=""
for candidate in \
  "$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast" \
  "$ROOT_DIR/.build/checkouts/Sparkle/generate_appcast"; do
  if [[ -x "$candidate" ]]; then
    GENERATE_APPCAST="$candidate"
    break
  fi
done

if [[ -z "$GENERATE_APPCAST" ]]; then
  echo "Could not find Sparkle generate_appcast. Run 'swift build' first."
  exit 1
fi

rm -rf "$ARCHIVES_DIR"
mkdir -p "$ARCHIVES_DIR"
cp "$DMG" "$ARCHIVES_DIR/"
cp "$NOTES" "$ARCHIVES_DIR/Mac-Dynamic-Island-$VERSION.md"

args=(
  --download-url-prefix "$DOWNLOAD_PREFIX"
  --embed-release-notes
  -o "$APPCAST"
  "$ARCHIVES_DIR"
)

if [[ -n "${SPARKLE_ED_PRIVATE_KEY:-}" ]]; then
  printf "%s" "$SPARKLE_ED_PRIVATE_KEY" | "$GENERATE_APPCAST" --ed-key-file - "${args[@]}"
else
  "$GENERATE_APPCAST" "${args[@]}"
fi

echo "已生成：$APPCAST"
