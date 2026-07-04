import AppKit

enum IconLoader {
    static func icon(for item: AppItem) -> NSImage {
        if let path = item.path {
            let image = NSWorkspace.shared.icon(forFile: path)
            if image.size != .zero {
                return image
            }
        }
        return NSImage(systemSymbolName: "app.fill", accessibilityDescription: item.name) ?? NSImage(size: .init(width: 64, height: 64))
    }
}
