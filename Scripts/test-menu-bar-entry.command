#!/bin/zsh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
swiftc -parse-as-library \
  "$ROOT_DIR/Sources/DynamicIsland/Managers/MenuBarEntry.swift" \
  "$ROOT_DIR/Scripts/MenuBarEntryChecks.swift" \
  -o "$WORK_DIR/menu-bar-entry-check"
"$WORK_DIR/menu-bar-entry-check"
