#!/bin/zsh
set -euo pipefail

VERSION="${VERSION:-1.0.1}"
TAG="v$VERSION"
REPO="${REPO:-weizhiyan/Mac-dynamic-island}"
DMG="Release/Mac-Dynamic-Island-$VERSION.dmg"
PKG="Release/Mac-Dynamic-Island-$VERSION.pkg"
PUBLIC_DMG="Downloads/Mac-Dynamic-Island-$VERSION.dmg"
PUBLIC_PKG="Downloads/Mac-Dynamic-Island-$VERSION.pkg"
NOTES="Docs/releases/v$VERSION.md"
DOWNLOAD_PREFIX="https://raw.githubusercontent.com/$REPO/main/Downloads/"

if [[ ! -f "$DMG" ]]; then
  echo "Missing $DMG. Building it now..."
  VERSION="$VERSION" ./Scripts/build-dmg.command
fi

if [[ ! -f "$PKG" ]]; then
  echo "Missing $PKG. Building it now..."
  VERSION="$VERSION" ./Scripts/build-pkg.command
fi

if [[ ! -f "$NOTES" ]]; then
  echo "Missing release notes: $NOTES"
  exit 1
fi

mkdir -p Downloads
ditto --norsrc --noextattr --noacl --noqtn "$DMG" "$PUBLIC_DMG"
ditto --norsrc --noextattr --noacl --noqtn "$PKG" "$PUBLIC_PKG"

DOWNLOAD_PREFIX="$DOWNLOAD_PREFIX" VERSION="$VERSION" REPO="$REPO" ./Scripts/generate-appcast.command

if [[ -n "$(git status --short -- appcast.xml "$PUBLIC_DMG" "$PUBLIC_PKG")" ]]; then
  git add appcast.xml "$PUBLIC_DMG" "$PUBLIC_PKG"
  git commit -m "Update appcast for $TAG"
fi

if ! git rev-parse "$TAG" >/dev/null 2>&1; then
  git tag -a "$TAG" -m "Mac Dynamic Island $VERSION"
fi

git push -u origin main
git push origin "$TAG"

echo "发布完成："
echo "$DOWNLOAD_PREFIX$(basename "$PUBLIC_DMG")"
echo "$DOWNLOAD_PREFIX$(basename "$PUBLIC_PKG")"
