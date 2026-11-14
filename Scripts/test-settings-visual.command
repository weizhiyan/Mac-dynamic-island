#!/bin/zsh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
SOURCES=("$ROOT_DIR"/Sources/DynamicIsland/**/*.swift)
SOURCES=("${(@)SOURCES:#*/AppEntry.swift}")
swiftc -O -parse-as-library "${SOURCES[@]}" "$ROOT_DIR/Scripts/SettingsVisualChecks.swift" -o "$WORK_DIR/settings-visual-check"
"$WORK_DIR/settings-visual-check" "${1:-$ROOT_DIR/Build/Verification}"
