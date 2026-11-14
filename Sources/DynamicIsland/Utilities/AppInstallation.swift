import AppKit

enum AppInstallation {
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "开发版")（\(info["CFBundleVersion"] as? String ?? "—")）"
    }

    static var path: String { Bundle.main.bundleURL.path }
    static var isInstalled: Bool {
        let parent = Bundle.main.bundleURL.deletingLastPathComponent().standardizedFileURL.path
        return parent == "/Applications" || parent == NSHomeDirectory() + "/Applications"
    }

    static func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    static func openActivityMonitor() {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.ActivityMonitor")
            ?? URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app")
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
