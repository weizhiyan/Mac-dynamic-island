import AppKit

/// 从头像图片里取一个压在纯黑上依然清晰的强调色，给收起态波纹用。
enum ArtworkTint {
    private static let gridSize = 24
    private static let hueBuckets = 24
    private static let minimumSaturation: CGFloat = 0.18
    private static let minimumBrightness: CGFloat = 0.12

    /// 返回 nil 表示头像基本是黑白灰，调用方应回退成白色波纹。
    static func color(from image: NSImage) -> NSColor? {
        var rect = NSRect.zero
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let count = gridSize * gridSize
        var pixels = [UInt8](repeating: 0, count: count * 4)
        guard let context = CGContext(
            data: &pixels,
            width: gridSize,
            height: gridSize,
            bitsPerComponent: 8,
            bytesPerRow: gridSize * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: gridSize, height: gridSize))

        var bucketWeight = [CGFloat](repeating: 0, count: hueBuckets)
        var bucketHue = [CGFloat](repeating: 0, count: hueBuckets)
        var bucketSaturation = [CGFloat](repeating: 0, count: hueBuckets)
        var bucketBrightness = [CGFloat](repeating: 0, count: hueBuckets)

        for index in 0..<count {
            let offset = index * 4
            guard pixels[offset + 3] > 128 else { continue }
            let (hue, saturation, brightness) = hsb(
                red: CGFloat(pixels[offset]) / 255,
                green: CGFloat(pixels[offset + 1]) / 255,
                blue: CGFloat(pixels[offset + 2]) / 255
            )
            guard saturation >= minimumSaturation, brightness >= minimumBrightness else { continue }
            let bucket = min(hueBuckets - 1, Int(hue * CGFloat(hueBuckets)))
            let weight = saturation * brightness
            bucketWeight[bucket] += weight
            bucketHue[bucket] += hue * weight
            bucketSaturation[bucket] += saturation * weight
            bucketBrightness[bucket] += brightness * weight
        }

        guard let best = bucketWeight.indices.max(by: { bucketWeight[$0] < bucketWeight[$1] }), bucketWeight[best] > 0 else { return nil }
        let weight = bucketWeight[best]
        let hue = normalize(bucketHue[best] / weight)
        let saturation = min(max(bucketSaturation[best] / weight, 0.45), 1)
        let brightness = min(max(bucketBrightness[best] / weight, 0.78), 1)
        return NSColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
    }

    private static func normalize(_ hue: CGFloat) -> CGFloat {
        var value = hue
        while value < 0 { value += 1 }
        while value >= 1 { value -= 1 }
        return value
    }

    private static func hsb(red: CGFloat, green: CGFloat, blue: CGFloat) -> (hue: CGFloat, saturation: CGFloat, brightness: CGFloat) {
        let maxChannel = max(red, green, blue)
        let minChannel = min(red, green, blue)
        let delta = maxChannel - minChannel
        let brightness = maxChannel
        let saturation = maxChannel == 0 ? 0 : delta / maxChannel
        guard delta > 0 else { return (0, saturation, brightness) }
        var hue: CGFloat
        if maxChannel == red {
            hue = (green - blue) / delta + (green < blue ? 6 : 0)
        } else if maxChannel == green {
            hue = (blue - red) / delta + 2
        } else {
            hue = (red - green) / delta + 4
        }
        return (hue / 6, saturation, brightness)
    }
}
