#!/bin/zsh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
swiftc -parse-as-library \
  "$ROOT_DIR/Sources/DynamicIsland/Utilities/CommandRunner.swift" \
  "$ROOT_DIR/Sources/DynamicIsland/Managers/SodaMusicController.swift" \
  "$ROOT_DIR/Sources/DynamicIsland/Managers/SodaSessionStarter.swift" \
  "$ROOT_DIR/Sources/DynamicIsland/Managers/SystemMetricsStore.swift" \
  "$ROOT_DIR/Scripts/PlaybackMetricsChecks.swift" \
  -o "$WORK_DIR/playback-metrics-check"
"$WORK_DIR/playback-metrics-check" "$@" "$ROOT_DIR/Sources/DynamicIsland/Resources/NowPlayingBridge.js"
