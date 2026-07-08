#!/bin/zsh
set -euo pipefail

VERSION="${VERSION:-1.0.1}"
TAG="v$VERSION"
REPO="${REPO:-weizhiyan/Mac-dynamic-island}"
PKG="Release/Mac-Dynamic-Island-$VERSION.pkg"
INTEL_PKG="Release/Mac-Dynamic-Island-$VERSION-intel.pkg"
PUBLIC_PKG="Downloads/Mac灵动岛_M芯片_$VERSION.pkg"
PUBLIC_INTEL_PKG="Downloads/Mac灵动岛_intel_$VERSION.pkg"
NOTES="Docs/releases/v$VERSION.md"
DOWNLOAD_PREFIX="https://raw.githubusercontent.com/$REPO/main/Downloads/"

if [[ ! -f "$PKG" ]]; then
  echo "Missing $PKG. Building it now..."
  VERSION="$VERSION" ./Scripts/build-pkg.command
fi

if [[ ! -f "$INTEL_PKG" ]]; then
  echo "Missing $INTEL_PKG. Building it now..."
  VERSION="$VERSION" BUILD_ARCH=x86_64 ./Scripts/build-pkg.command
fi

if [[ ! -f "$NOTES" ]]; then
  echo "Missing release notes: $NOTES"
  exit 1
fi

mkdir -p Downloads
rm -f Downloads/Mac-Dynamic-Island-"$VERSION"*.dmg(N)
rm -f Downloads/Mac-Dynamic-Island-"$VERSION".pkg Downloads/Mac-Dynamic-Island-"$VERSION"-intel.pkg
rm -f Downloads/Mac-Dynamic-Island-"$VERSION"-Apple-Silicon.pkg Downloads/Mac-Dynamic-Island-"$VERSION"-Intel.pkg
ditto --norsrc --noextattr --noacl --noqtn "$PKG" "$PUBLIC_PKG"
ditto --norsrc --noextattr --noacl --noqtn "$INTEL_PKG" "$PUBLIC_INTEL_PKG"

if [[ -n "$(git status --short -- Downloads)" ]]; then
  git add -u Downloads
  git add "$PUBLIC_PKG" "$PUBLIC_INTEL_PKG"
  git commit -m "Update installers for $TAG"
fi

if ! git rev-parse "$TAG" >/dev/null 2>&1; then
  git tag -a "$TAG" -m "Mac Dynamic Island $VERSION"
fi

git push -u origin main
git push origin "$TAG"

echo "发布完成："
echo "$DOWNLOAD_PREFIX$(basename "$PUBLIC_PKG")"
echo "$DOWNLOAD_PREFIX$(basename "$PUBLIC_INTEL_PKG")"
