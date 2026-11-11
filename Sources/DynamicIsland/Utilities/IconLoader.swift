import AppKit

enum IconLoader {
    private static let cache = NSCache<NSString, NSImage>()
    static func icon(for item: AppItem) -> NSImage {
        if let path = item.path {
            if let cached = cache.object(forKey: path as NSString) { return cached }
            let image = NSWorkspace.shared.icon(forFile: path)
            if image.size != .zero {
                cache.countLimit = 128
                cache.setObject(image, forKey: path as NSString)
                return image
            }
        }
        return NSImage(systemSymbolName: "app.fill", accessibilityDescription: item.name) ?? NSImage(size: .init(width: 64, height: 64))
    }
}
