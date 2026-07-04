#!/bin/zsh
set -euo pipefail

VERSION="1.0.0"
TAG="v$VERSION"
REPO="weizhiyan/Mac-dynamic-island"
DMG="Release/Mac-Dynamic-Island-$VERSION.dmg"
NOTES="Release/RELEASE_NOTES_v$VERSION.md"

if [[ ! -f "$DMG" ]]; then
  echo "Missing $DMG. Run: NO_OPEN=1 ./LaunchDynamicIsland.command"
  exit 1
fi

git push -u origin main
git push origin "$TAG"

if command -v gh >/dev/null 2>&1; then
  gh release create "$TAG" "$DMG" \
    --repo "$REPO" \
    --title "Mac Dynamic Island $VERSION" \
    --notes-file "$NOTES"
else
  echo "GitHub CLI (gh) is not installed, so the code/tag were pushed but the GitHub Release asset was not uploaded."
  echo "Install gh, run 'gh auth login', then run this script again."
fi
