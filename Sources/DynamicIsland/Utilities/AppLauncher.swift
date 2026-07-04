import AppKit

struct AppLauncher {
    static func launch(_ item: AppItem) {
        guard let urlString = item.path else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: urlString))
    }
}
