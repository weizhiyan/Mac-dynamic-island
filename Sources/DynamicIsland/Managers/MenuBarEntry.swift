import AppKit
import Combine

final class MenuBarEntry: ObservableObject {
    static let shared = MenuBarEntry()
    static let autosaveName = "DynamicIsland.MainControl"
    static let migrationKey = "DynamicIsland.MainControlVisibilityVersion"

    @Published private(set) var recoveryMessage: String?
    @Published private(set) var isRecovering = false

    static func prepareDefaults(_ defaults: UserDefaults = .standard, restoring: Bool = false) {
        guard restoring || defaults.integer(forKey: migrationKey) < 2 else { return }
        // AppKit briefly uses Item-0 before the explicit autosave name is attached.
        for name in ["Item-0", autosaveName] {
            defaults.set(true, forKey: "NSStatusItem Visible \(name)")
            defaults.set(true, forKey: "NSStatusItem VisibleCC \(name)")
            let positionKey = "NSStatusItem Preferred Position \(name)"
            if restoring || defaults.object(forKey: positionKey) == nil {
                defaults.set(0.0, forKey: positionKey)
            }
        }
        defaults.set(2, forKey: migrationKey)
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.MenuBarSettings") else { return }
        NSWorkspace.shared.open(url)
    }

    func beginRecovery() {
        isRecovering = true
        recoveryMessage = "正在恢复菜单栏入口…"
    }

    func check(_ item: NSStatusItem, reportRecovery: Bool = false) {
        let frame = item.button?.window?.frame
        let locatedInMenuBar = frame.map { frame in
            NSScreen.screens.contains { screen in
                Self.isInMenuBar(frame, screenFrame: screen.frame,
                                 menuBarHeight: max(screen.safeAreaInsets.top, NSStatusBar.system.thickness))
            }
        } ?? false
        NSLog("DynamicIsland menu entry: visible=%d frame=%@ inMenuBar=%d",
              item.isVisible, frame.map(NSStringFromRect) ?? "none", locatedInMenuBar)
        if reportRecovery {
            isRecovering = false
            recoveryMessage = locatedInMenuBar
                ? "入口位置已回到菜单栏。若仍看不到，请检查系统菜单栏设置。"
                : "尚未确认图标显示，请检查系统菜单栏设置中的“允许在菜单栏显示”。"
        }
    }

    static func isInMenuBar(_ frame: CGRect, screenFrame: CGRect, menuBarHeight: CGFloat) -> Bool {
        guard !frame.isNull, frame.width > 0, frame.height > 0 else { return false }
        let menuBar = CGRect(x: screenFrame.minX, y: screenFrame.maxY - menuBarHeight,
                             width: screenFrame.width, height: menuBarHeight)
        return menuBar.contains(CGPoint(x: frame.midX, y: frame.midY))
    }
}
