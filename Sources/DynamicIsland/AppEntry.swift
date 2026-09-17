import SwiftUI
import AppKit
import Sparkle
import Combine

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
    private var screenObservers: [NSObjectProtocol] = []
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    private var isIslandEnabled = true
    private var menuBarPopover: NSPopover?
    private var popoverJustClosed = false
    private var popoverEventMonitors: [Any] = []
    /// 移动图标前弹窗是否开着 —— 决定移动完要不要弹回来
    private var popoverWasOpenBeforeMove = false
    private var cancellables = Set<AnyCancellable>()

    deinit {
        let center = NotificationCenter.default
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        screenObservers.forEach {
            center.removeObserver($0)
            workspaceCenter.removeObserver($0)
        }
        screenObservers.removeAll()
        removePopoverEventMonitors()
        MenuBarIconManager.shared.stop()
    }

    func applicationWillTerminate(_ notification: Notification) {
        MenuBarIconManager.shared.stop()
    }

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
            },
            onScreenChanged: { [weak self] in
                self?.refreshWindowGeometry()
            }
        )
        detectorWindow = detector
        setupScreenObservers()
        setupStatusItem()
        setupMenuBarIconManager()

        if ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_PREVIEW"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                self.islandWindow?.showIsland()
            }
        }

        // 实测新的「零指针位移」移动方案，只在设了环境变量时跑（见 MenuBarProProbe）。
        MenuBarProProbe.runIfRequested()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    private func setupScreenObservers() {
        let center = NotificationCenter.default
        screenObservers.append(
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                self?.refreshWindowGeometry()
            }
        )
        screenObservers.append(
            NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.refreshWindowGeometry()
            }
        )
    }

    private func refreshWindowGeometry() {
        islandWindow?.refreshForCurrentScreen()
        detectorWindow?.refreshScreenGeometry()
    }

    // MARK: - 菜单栏图标收纳管理

    private func setupMenuBarIconManager() {
        MenuBarIconManager.shared.start()

        // 合成 ⌘ 拖拽期间弹窗必须关掉：开着的 popover 会吞掉鼠标事件，图标一动不动。
        // 移动结束后如果之前是开着的就弹回来，让用户直接看到结果。
        MenuBarIconManager.shared.onMoveWillBegin = { [weak self] in
            self?.popoverWasOpenBeforeMove = self?.menuBarPopover?.isShown == true
            self?.closeMenuBarPopover()
        }
        MenuBarIconManager.shared.onMoveDidEnd = { [weak self] in
            guard self?.popoverWasOpenBeforeMove == true else { return }
            self?.popoverWasOpenBeforeMove = false
            self?.showMenuBarPopover()
        }

        // 收纳成员来自实时 AX 判定，没有本地名单要同步；
        // 这里只在图标库变化时重算弹窗尺寸（订阅一次，别放到 showMenuBarPopover 里累积）。
        MenuBarIconManager.shared.$allIcons
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updatePopoverSize() }
            .store(in: &cancellables)

        MenuBarIconManager.shared.$isArranging
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updatePopoverSize() }
            .store(in: &cancellables)
    }

    private func setupStatusItem() {
        let statusItemName = "DynamicIsland.MainControl"
        let preferredPositionKey = "NSStatusItem Preferred Position \(statusItemName)"
        if UserDefaults.standard.object(forKey: preferredPositionKey) == nil {
            UserDefaults.standard.set(0.0, forKey: preferredPositionKey)
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = statusItemName
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
        button.target = self
        button.action = #selector(statusItemClicked)
    }

    // MARK: - 菜单栏气泡弹窗

    @objc private func statusItemClicked() {
        // 防止 popover 被 .transient 关闭后立即重新弹出（闪烁）
        if popoverJustClosed {
            popoverJustClosed = false
            return
        }
        if menuBarPopover?.isShown == true {
            closeMenuBarPopover()
        } else {
            menuBarPopover = nil
            MenuBarIconManager.shared.clearMoveMessage()
            showMenuBarPopover()
        }
    }

    private func showMenuBarPopover() {
        // 打开弹窗前刷新一次菜单栏图标枚举与快照，保证候选列表最新
        MenuBarIconManager.shared.refresh()
        let pop = NSPopover()
        pop.behavior = .transient       // 点击外部自动关闭
        pop.animates = true             // 原生弹出动画
        pop.delegate = self

        let view = MenuBarPopoverView(
            isIslandEnabled: isIslandEnabled,
            onToggleIsland: { [weak self] in
                self?.closeMenuBarPopover()
                if self?.isIslandEnabled == true {
                    self?.hideIsland()
                } else {
                    self?.showIsland()
                }
            },
            onSettings: { [weak self] in
                self?.closeMenuBarPopover()
                self?.openSettings()
            },
            onCheckUpdates: { [weak self] in
                self?.closeMenuBarPopover()
                self?.checkForUpdates()
            },
            onQuit: { [weak self] in
                self?.closeMenuBarPopover()
                NSApp.terminate(nil)
            }
        )
        .environmentObject(AppStore.shared)
        .environmentObject(SettingsStore.shared)

        pop.contentViewController = NSHostingController(rootView: AnyView(view))

        // 预布局一次获取内容的实际尺寸，实现自适应
        if let hostingView = pop.contentViewController?.view {
            hostingView.layoutSubtreeIfNeeded()
            let fittingSize = hostingView.fittingSize
            pop.contentSize = NSSize(width: ceil(fittingSize.width), height: ceil(fittingSize.height))
        }

        if let button = statusItem?.button {
            pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        menuBarPopover = pop
        installPopoverDismissMonitors()
    }

    private func closeMenuBarPopover() {
        removePopoverEventMonitors()
        menuBarPopover?.close()
        menuBarPopover = nil
    }

    private func installPopoverDismissMonitors() {
        removePopoverEventMonitors()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.dismissPopoverIfClickedOutside(event)
            return event
        }
        let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.dismissPopoverIfClickedOutside(event)
        }
        if let localMonitor { popoverEventMonitors.append(localMonitor) }
        if let globalMonitor { popoverEventMonitors.append(globalMonitor) }
    }

    private func removePopoverEventMonitors() {
        popoverEventMonitors.forEach { NSEvent.removeMonitor($0) }
        popoverEventMonitors.removeAll()
    }

    private func dismissPopoverIfClickedOutside(_ event: NSEvent) {
        guard let popover = menuBarPopover, popover.isShown,
              let popoverWindow = popover.contentViewController?.view.window else { return }
        let location = event.window?.convertToScreen(
            NSRect(origin: event.locationInWindow, size: .zero)
        ).origin ?? NSEvent.mouseLocation
        guard !popoverWindow.frame.contains(location) else { return }
        if let statusWindow = statusItem?.button?.window,
           statusWindow.frame.contains(location) {
            return
        }
        closeMenuBarPopover()
    }

    /// 根据当前内容更新弹窗尺寸（收纳列表变化时调用）
    private func updatePopoverSize() {
        guard let pop = menuBarPopover,
              let hostingView = pop.contentViewController?.view else { return }
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        pop.contentSize = NSSize(width: ceil(size.width), height: ceil(size.height))
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

    @objc func openSettings() {
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

    func addShortcutAppsFromPanel() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.title = "选择应用"
        panel.prompt = "添加"
        panel.message = "可以一次选择多个应用"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true

        if panel.runModal() == .OK {
            AppStore.shared.addApps(at: panel.urls)
        }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

// MARK: - NSPopoverDelegate

extension AppDelegate: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        removePopoverEventMonitors()
        menuBarPopover = nil
        // 标记刚刚关闭，防止 statusItemClicked 立即重新弹出（闪烁）
        popoverJustClosed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.popoverJustClosed = false
        }
    }
}
