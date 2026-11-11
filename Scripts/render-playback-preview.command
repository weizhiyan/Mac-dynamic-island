#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT_DIR/Sources/DynamicIsland"
WORK_DIR="$(mktemp -d)"
OUTPUT_PATH="${1:-/tmp/dynamic-island-playback-preview.png}"
trap 'rm -rf "$WORK_DIR"' EXIT

cat > "$WORK_DIR/main.swift" <<'SWIFT'
import AppKit
import QuartzCore

let bandWidth: CGFloat = 289
let bandHeight: CGFloat = 38
let scale: CGFloat = 2

func artwork() -> NSImage {
    let image = NSImage(size: NSSize(width: 96, height: 96))
    image.lockFocus()
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.95, green: 0.28, blue: 0.34, alpha: 1),
        NSColor(calibratedRed: 0.46, green: 0.18, blue: 0.62, alpha: 1)
    ])!
    gradient.draw(in: NSRect(x: 0, y: 0, width: 96, height: 96), angle: -45)
    let symbol = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)!
    symbol.isTemplate = true
    NSColor.white.withAlphaComponent(0.88).set()
    symbol.draw(in: NSRect(x: 28, y: 28, width: 40, height: 40))
    image.unlockFocus()
    return image
}

let canvas = NSView(frame: NSRect(x: 0, y: 0, width: bandWidth, height: bandHeight))
canvas.wantsLayer = true
canvas.layer?.backgroundColor = NSColor(calibratedWhite: 0.13, alpha: 1).cgColor

let band = NSView(frame: canvas.bounds)
band.wantsLayer = true
band.layer?.backgroundColor = NSColor.black.cgColor
band.layer?.cornerRadius = bandHeight * NotchDetector.notchBottomRadiusRatio
canvas.addSubview(band)

let media = CompactMediaView(frame: band.bounds)
band.addSubview(media)
media.layoutSubtreeIfNeeded()
media.update(
    image: artwork(),
    mode: .playing,
    tint: NSColor(calibratedRed: 1.0, green: 0.48, blue: 0.58, alpha: 1),
    progress: 0.42,
    animates: false,
    progressAnimates: false
)
media.layoutSubtreeIfNeeded()

let bitmap = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
bitmap.size = canvas.bounds.size
canvas.cacheDisplay(in: canvas.bounds, to: bitmap)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode preview PNG")
}
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SWIFT

swiftc -O \
  "$SRC/Utilities/NotchDetector.swift" \
  "$SRC/Utilities/ArtworkTint.swift" \
  "$SRC/Views/CompactMediaView.swift" \
  "$SRC/Views/WaveformLayer.swift" \
  "$WORK_DIR/main.swift" \
  -o "$WORK_DIR/playback-preview"

"$WORK_DIR/playback-preview" "$OUTPUT_PATH"
print "已生成播放态预览：$OUTPUT_PATH"
