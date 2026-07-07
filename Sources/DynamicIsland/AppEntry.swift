import SwiftUI
import AppKit
import Sparkle

@main
struct DynamicIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(SettingsStore.shared)
                .environmentObject(AppStore.shared)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?

    private var islandWindow: IslandWindowController?
    private var detectorWindow: HoverDetectorWindowController?
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private var isIslandEnabled = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self
        print("DynamicIsland: didFinishLaunching")
        NSApp.setActivationPolicy(.accessory)
        _ = updaterController

        let island = IslandWindowController()
        islandWindow = island

        let detector = HoverDetectorWindowController(
            islandFrameProvider: { [weak self] in
                // 只有展开时才返回 window.frame，收缩态返回 nil
                // 这样收缩态只用 activationZone（顶部窄条）触发，不会误触
                guard let island = self?.islandWindow, island.isExpanded,
                      let window = island.window, window.alphaValue > 0.01 else { return nil }
                return window.frame
            },
            onEnter: { [weak self] in
                guard self?.isIslandEnabled == true else { return }
                self?.islandWindow?.showIsland()
            },
            onLeave: { [weak self] in
                guard self?.isIslandEnabled == true else { return }
                self?.islandWindow?.hideIsland()
            }
        )
        detectorWindow = detector
        setupStatusItem()

        if ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_PREVIEW"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.islandWindow?.showIsland()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item
        guard let button = item.button else { return }
        let statusImage = Bundle.module.url(forResource: "StatusIcon", withExtension: "png")
            .flatMap(NSImage.init(contentsOf:))
            ?? NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "灵动岛")
        statusImage?.isTemplate = true
        statusImage?.size = NSSize(width: 18, height: 18)
        button.image = statusImage
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        let menu = NSMenu()
        menu.addItem(withTitle: "显示灵动岛", action: #selector(showIsland), keyEquivalent: "s")
        menu.addItem(withTitle: "隐藏灵动岛", action: #selector(hideIsland), keyEquivalent: "h")
        menu.addItem(.separator())
        menu.addItem(withTitle: "检查更新...", action: #selector(checkForUpdates), keyEquivalent: "u")
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置...", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
    }

    @objc private func showIsland() {
        isIslandEnabled = true
        islandWindow?.showIsland()
    }

    @objc private func hideIsland() {
        isIslandEnabled = false
        islandWindow?.hideIslandImmediately()
    }
    func showTriggerAreaPreview() { detectorWindow?.showActivationZonePreview() }

    @objc func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            // 手动创建设置窗口（.accessory 模式下 SwiftUI Settings scene 可能不响应）
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered, defer: false)
            window.title = "灵动岛设置"
            window.isReleasedWhenClosed = false
            window.center()
            let host = NSHostingView(rootView: AnyView(
                SettingsView().environmentObject(SettingsStore.shared)
                    .environmentObject(AppStore.shared)
            ))
            host.translatesAutoresizingMaskIntoConstraints = false
            window.contentView = host
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
