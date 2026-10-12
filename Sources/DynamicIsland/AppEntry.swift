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
    private var customizeWindow: NSWindow?
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

    /// 自定义面板顶部与屏幕顶端的最小间距（pt），给展开态灵动岛留位置。
    private static let customizeWindowTopMargin: CGFloat = 220

    func applicationWillTerminate(_ notification: Notification) {
        MenuBarIconManager.shared.stop()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard enforceSingleInstance() else { return }
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

    /// 安装包覆盖旧版本后，用户可能会从 Finder 再次打开应用。
    /// 同一 bundle ID 只允许一个进程持有菜单栏和灵动岛窗口。
    private func enforceSingleInstance() -> Bool {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let bundleID = Bundle.main.bundleIdentifier ?? "com.zhiyan.dynamicisland"
        let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != currentPID }
        guard let existing else { return true }

        existing.activate()
        NSApp.terminate(nil)
        return false
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
        // 刷新走后台队列（见 MenuBarIconManager.refresh），不会拖住弹窗弹出
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

    /// 设置页「试一下」：不吊嗓子等悬停，直接播一遍展开→收起，方便对照动画参数。
    func testIslandAnimation() { islandWindow?.testExpand() }

    @objc func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            // 手动创建设置窗口（.accessory 模式下 SwiftUI Settings scene 可能不响应）
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "灵动岛设置"
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 760, height: 560)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
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

    // MARK: - 自定义岛屿面板

    /// 打开「自定义灵动岛」面板：同时强制展开真实岛屿做实时预览。
    @objc func openCustomizePanel() {
        closeMenuBarPopover()
        if customizeWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 780),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "自定义灵动岛"
            window.isReleasedWhenClosed = false
            window.delegate = self
            // 跟随所有空间：编辑面板要能和真实灵动岛同屏，全屏应用里也能浮出来
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            let host = NSHostingView(rootView: AnyView(
                IslandCustomizeView(
                    onDone: { [weak self] in
                        self?.closeCustomizePanel()
                    },
                    onPreviewModeChanged: { [weak self] expanded in
                        self?.islandWindow?.setLivePreviewExpanded(expanded)
                    }
                )
                .environmentObject(SettingsStore.shared)
                .environmentObject(AppStore.shared)
                .environmentObject(IslandViewModel.shared)
                .environmentObject(MediaPlayerStore.shared)
                .environmentObject(SystemMetricsStore.shared)
            ))
            window.contentView = host
            customizeWindow = window
        }
        positionCustomizeWindow()
        NSApp.activate(ignoringOtherApps: true)
        customizeWindow?.makeKeyAndOrderFront(nil)
        islandWindow?.beginLivePreview()
    }

    /// 面板落在灵动岛下方：真实岛屿贴在屏幕顶端，两者不能互相遮挡。
    private func positionCustomizeWindow() {
        guard let window = customizeWindow, let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = window.frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: max(visible.minY, visible.maxY - Self.customizeWindowTopMargin - size.height)
        )
        window.setFrameOrigin(origin)
    }

    func closeCustomizePanel() {
        customizeWindow?.close()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === customizeWindow else { return }
        // 面板关闭：解除实时预览锁定，岛屿回到悬停控制
        islandWindow?.endLivePreview()
    }
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
