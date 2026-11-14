import AppKit
import SwiftUI

// The rendering harness never launches the island or sends playback commands.
final class AppDelegate {
    static var shared: AppDelegate?
    func restoreMenuBarIcon() {}
    func openCustomizePanel() {}
    func checkForUpdates() {}
    func showTriggerAreaPreview() {}
    func testIslandAnimation() {}
    func openSettings() {}
}

@main
struct SettingsVisualChecks {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        UserDefaults.standard.set(11, forKey: "settingsVersion")
        UserDefaults.standard.set("com.soda.music", forKey: "mediaPlayerBundleID")
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let scenarios = SettingsPane.allCases.map { ($0, false) } + [(.music, true)]
            for (pane, denied) in scenarios {
                try autoreleasepool {
                    let size = NSSize(width: 760, height: 560)
                    let permission = denied ? AccessibilityPermission(check: { false }) : .shared
                    let view = SettingsView(initialPane: pane, accessibility: permission)
                        .environmentObject(SettingsStore.shared)
                        .environmentObject(AppStore.shared)
                    let host = NSHostingView(rootView: view)
                    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
                    window.appearance = NSAppearance(named: appearance)
                    window.contentView = host
                    host.frame = NSRect(origin: .zero, size: size)
                    host.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("No bitmap") }
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    guard let data = bitmap.representation(using: .png, properties: [:]), data.count > 10_000 else { fatalError("Empty render") }
                    let name = "settings-\(pane.rawValue)\(denied ? "-denied" : "")-\(appearance == .aqua ? "light" : "dark").png"
                    try data.write(to: output.appendingPathComponent(name))
                    print("Rendered \(name): \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
                    window.contentView = nil
                }
            }
        }
    }
}
