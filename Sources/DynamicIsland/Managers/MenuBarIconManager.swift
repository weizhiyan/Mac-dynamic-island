import AppKit
import ApplicationServices

/// 菜单栏状态项当前的可见性。
enum MenuBarIconVisibility {
    /// frame 落在菜单栏可见区内 —— 用户在菜单栏上直接看得到、点得到。
    case visible
    /// 位置读到了，但已被 macOS 挤出可见区（收纳分隔符或刘海所致）。
    /// 实测被挤出的状态项仍停在菜单栏那一条高度上，只是横向被推到屏幕外
    /// （例如 x = -3902, y = 7），也见过整条被抬到所有屏幕上方（y = -1437）。
    case hidden
    /// 应用建了状态项但根本没放到菜单栏上（自己 isVisible = false，或系统没给它槽位）。
    /// 实测这种会停在主屏底部之外：Figma 常年是 (-1, 1168, 34, 24)，
    /// 和一个拿不到槽位的 NSStatusItem 完全同一个签名。
    /// 它既不在菜单栏上，也不是被我们收纳的 —— 两栏都不该显示，否则点了什么也不会发生。
    case notDisplayed
    /// AX 读取失败（进程忙 / 超时）。沿用上一轮判定，避免图标在两个分区之间来回跳。
    case unknown
}

/// 菜单栏图标信息：通过 Accessibility API 获取
struct MenuBarIconInfo {
    let bundleID: String
    let appName: String
    /// 应用图标。弹窗统一用它显示：始终清晰、零权限、不受壁纸和深浅色影响。
    let icon: NSImage
    /// AXUIElement 引用，用于模拟点击（kAXPressAction）
    let axElement: AXUIElement?
    /// 最近一次读到的 frame（Quartz 坐标，左上角原点），仅用于判定与诊断
    let quartzFrame: CGRect
    let visibility: MenuBarIconVisibility
}

/// 菜单栏图标收纳（Hidden Bar / Ice / Dozer 同款「边界」模型）。
///
/// 三条设计前提，都是踩过坑之后定下来的：
///
/// 1. **隐藏只能靠边界。** macOS 没有任何公开 API 能移动别的应用的状态项，
///    唯一能真正释放菜单栏空间的办法是自建一个超长的分隔符 NSStatusItem，
///    由 macOS 把它左侧的图标原生挤出可见区。所以「收纳某个图标」本质上就是
///    「把它挪到分隔符左边」，而挪动只能靠合成用户那套 ⌘ 拖拽
///    （见 MenuBarItemMover）。合成拖拽不保证每个应用都吃，所以每次移动后都要
///    复查 frame 真的换了边；两种投递方式都失败时提示用户走「整理」手动拖。
/// 2. **显示状态以 AX 为准，用户意图单独落盘。** 收纳区仍直接读取「AX 报告已被挤出可见区」；
///    只有用户明确点击过收纳 / 恢复的图标才记录偏好，用于重启或唤醒后的状态校正。
///    没被用户操作过、只是被刘海挤掉的图标不会被误记成收纳。
/// 3. **统一显示应用图标。** ScreenCaptureKit 真实快照已移除：需要屏幕录制权限、
///    图标隐藏时根本截不到，且旧实现三处换算都是错的（SCDisplay.width 是点不是像素
///    导致恒定 1x、条带高度按 NSStatusBar.thickness=22 裁而图标 frame 到 y=27 底部被切、
///    NSImage 尺寸按点算导致纵向拉伸），落到弹窗里就是一团糊。
/// 4. **「有状态项」不等于「在菜单栏上」。** 有些应用（实测 Figma）常年挂着一个
///    没被放上菜单栏的状态项，AX 照样枚举得到。它停在主屏底部之外，
///    和被我们挤出去的那种（还停在菜单栏高度上）签名不同，靠 classify 区分开，
///    归为 .notDisplayed，两栏都不显示 —— 否则用户会看到一个点了没反应的图标。
final class MenuBarIconManager: ObservableObject {

    // MARK: - Singleton

    static let shared = MenuBarIconManager()
    private init() {}

    // MARK: - State

    /// 所有检测到的菜单栏图标 key: bundleID
    @Published private(set) var allIcons: [String: MenuBarIconInfo] = [:]
    /// 整理模式：分隔符变成可见窄条，左侧图标全部现身，等用户 ⌘ 拖拽
    @Published private(set) var isArranging = false
    @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
    /// 正在等某个图标的菜单弹出（期间禁止再次点击，避免分隔符状态打架）
    @Published private(set) var pressingBundleID: String?
    /// 正在移动（收纳 / 恢复）的图标，UI 上显示转圈
    @Published private(set) var movingBundleID: String?
    /// 上一次移动失败的原因，成功则为 nil
    @Published private(set) var lastMoveMessage: String?

    private var observers: [NSObjectProtocol] = []
    private var refreshTimer: DispatchSourceTimer?
    private var arrangeEndWorkItem: DispatchWorkItem?
    private var restoringSavedPreferences = false
    private var pendingSavedPreferenceRestores: [String] = []
    /// 合成拖拽要按毫秒节拍等待，只能在后台队列跑，否则主线程会卡住
    private let moveQueue = DispatchQueue(label: "com.zhiyan.dynamicisland.menubar-move")
    /// 移动开始前 / 结束后回调。合成拖拽的鼠标事件会被开着的 popover 吞掉
    /// （实测两次尝试图标一点没动，关掉弹窗后 6/6 成功），
    /// 所以必须先让 AppDelegate 关掉弹窗，移动完再弹回来。
    var onMoveWillBegin: (() -> Void)?
    var onMoveDidEnd: (() -> Void)?

    private var ownBundleID: String { Bundle.main.bundleIdentifier ?? "" }
    private let excludedSystemBundleIDs: Set<String> = [
        "com.apple.TextInputMenuAgent"
    ]
    private let savedStashBundleIDsKey = "DynamicIsland.MenuBar.StashedBundleIDs"
    private let savedVisibleBundleIDsKey = "DynamicIsland.MenuBar.VisibleBundleIDs"
    /// 整理模式持续时间：留给用户 ⌘ 拖图标，到时自动恢复隐藏
    let arrangeDuration: TimeInterval = 20

    // MARK: - 权限

    /// 弹出系统授权框并跳转系统设置
    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 启动 / 停止

    func start() {
        MenuBarSectionHider.shared.installIfNeeded()
        setupObservers()
        // 延迟首次枚举，等菜单栏上的其他应用把状态项都建好
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshNow()
        }
    }

    func stop() {
        observers.forEach {
            NotificationCenter.default.removeObserver($0)
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
        observers.removeAll()
        refreshTimer?.cancel()
        refreshTimer = nil
        arrangeEndWorkItem?.cancel()
        arrangeEndWorkItem = nil
        // 卸载分隔符，被收纳的图标恢复显示
        MenuBarSectionHider.shared.uninstall()
        allIcons.removeAll()
    }

    private func after(_ delay: TimeInterval, work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    // MARK: - 两个分区

    /// 收纳区：当前被挤出可见菜单栏的图标 —— 我们的分隔符挤的，或刘海挤的。
    /// 判定完全来自实时 AX，所以应用一退出条目就消失，不需要任何本地名单。
    func stashedIcons() -> [MenuBarIconInfo] {
        sortedByName(allIcons.values.filter { $0.visibility == .hidden })
    }

    /// 镜像区：菜单栏上当前可见的图标。点它等于点菜单栏本体，方便统一入口。
    func visibleIcons() -> [MenuBarIconInfo] {
        sortedByName(allIcons.values.filter { $0.visibility == .visible })
    }

    private func sortedByName(_ icons: [MenuBarIconInfo]) -> [MenuBarIconInfo] {
        icons.sorted { $0.appName.localizedStandardCompare($1.appName) == .orderedAscending }
    }

    // MARK: - 整理模式：让用户 ⌘ 拖图标跨过分隔符

    /// 把分隔符收成可见窄条，左侧图标全部现身，用户按住 ⌘ 拖动即可加入/移出收纳。
    /// arrangeDuration 秒后自动恢复隐藏，免得用户忘了关。
    func beginArrange() {
        arrangeEndWorkItem?.cancel()
        MenuBarSectionHider.shared.expand()
        isArranging = true
        after(0.3) { self.refreshNow() }
        let work = DispatchWorkItem { [weak self] in self?.endArrange() }
        arrangeEndWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + arrangeDuration, execute: work)
    }

    func endArrange() {
        arrangeEndWorkItem?.cancel()
        arrangeEndWorkItem = nil
        MenuBarSectionHider.shared.collapse()
        isArranging = false
        // 等 macOS 重排完菜单栏再读，否则读到的还是展开时的位置
        after(0.4) { self.refreshNow() }
    }

    // MARK: - 角标：收纳 / 恢复单个图标

    /// 把某个图标挪到分隔符左边 —— 也就是收纳起来。
    func stash(bundleID: String) { move(bundleID: bundleID, toStash: true) }

    /// 把某个图标挪回分隔符右边 —— 恢复到菜单栏上。
    func unstash(bundleID: String) { move(bundleID: bundleID, toStash: false) }

    /// 把图标挪过分隔符的两种手段，按顺序试。
    private enum MoveStrategy: CaseIterable {
        /// 新方案：两个写了 windowID 的事件（命中测试认字段不认指针），
        /// 全程隐藏指针、结束把指针复位到原处 —— 用户看不到任何跳动。
        case invisible
        /// 老方案：完整 ⌘ 拖拽 + 指针跟着走。新方案不吃的场景靠它兜底。
        case cursorDrag

        var label: String { self == .invisible ? "零位移" : "指针拖拽" }
    }

    /// 流程：关掉弹窗（否则它会吃掉合成的鼠标事件）→ 把分隔符收成窄条
    /// （图标全部现身、边界可见）→ 读新 frame → 后台合成 ⌘ 拖拽 →
    /// 拿移动后的边界复查是否真的换了边 → 恢复隐藏 → 重新枚举 → 弹窗回来。
    private func move(bundleID: String, toStash: Bool) {
        guard movingBundleID == nil, pressingBundleID == nil else { return }
        guard accessibilityGranted else {
            lastMoveMessage = "需要「辅助功能」权限才能移动菜单栏图标"
            return
        }
        movingBundleID = bundleID
        lastMoveMessage = nil
        let wasArranging = isArranging
        onMoveWillBegin?()
        MenuBarSectionHider.shared.expand()

        // 0.6s：等弹窗关闭动画走完 + macOS 把分隔符左边的图标重排回可见区
        after(0.6) {
            guard let info = self.allIcons[bundleID], let element = info.axElement,
                  let pid = self.ownerPID(of: bundleID) else {
                self.finishMove(
                    wasArranging: wasArranging, bundleID: bundleID, toStash: toStash,
                    message: "读不到这个图标了"
                )
                return
            }
            let name = info.appName
            let dividerWindowID = MenuBarSectionHider.shared.dividerWindowID()
            // 位置全部在后台队列里读：查自己的 AX（分隔符）要由主线程应答，
            // 在主线程上问会互等。
            self.moveQueue.async {
                guard let initial = self.alignedFrames(of: element) else {
                    self.finishMoveOnMain(
                        wasArranging: wasArranging, bundleID: bundleID, toStash: toStash,
                        message: "读不准菜单栏位置，稍后再试一次"
                    )
                    return
                }
                // 已经在目标那一侧就不用折腾了
                if (initial.item.midX < initial.divider.midX) == toStash {
                    self.finishMoveOnMain(
                        wasArranging: wasArranging, bundleID: bundleID, toStash: toStash,
                        message: nil
                    )
                    return
                }
                var succeeded = false
                var tried: [String] = []
                var shot: (from: CGPoint, target: CGPoint, divider: CGRect)?
                for strategy in MoveStrategy.allCases {
                    // 每次尝试都重读：上一次可能已经把图标挪动了一截，
                    // 而且图标换边后分隔符自己也会跟着挪。
                    guard let live = self.alignedFrames(of: element) else {
                        tried.append("\(strategy.label)→读不准位置")
                        continue
                    }
                    let from = CGPoint(x: live.item.midX, y: live.item.midY)
                    let target = CGPoint(
                        x: toStash ? live.divider.minX - 12 : live.divider.maxX + 12,
                        y: live.divider.midY
                    )
                    if shot == nil { shot = (from, target, live.divider) }
                    let detail: String
                    switch strategy {
                    case .invisible:
                        if let window = MenuBarWindowBridge.window(at: from) {
                            let anchorID = MenuBarWindowBridge.window(at: target)?.windowID
                                ?? dividerWindowID
                            detail = MenuBarItemMoverPro.move(
                                itemFrame: live.item, itemWindowID: window.windowID, pid: pid,
                                to: target, targetWindowID: anchorID
                            ).log
                        } else {
                            detail = "拿不到 windowID"
                        }
                    case .cursorDrag:
                        MenuBarItemMover.commandDrag(
                            from: from, to: target, ownerPID: pid, delivery: .hidTap
                        )
                        detail = "指针跟随"
                    }
                    usleep(300_000)
                    let settled = self.alignedFrames(of: element)
                    tried.append(
                        "\(strategy.label)[\(detail)]→"
                        + (settled.map { "\(Int($0.item.midX))|界\(Int($0.divider.midX))" }
                            ?? "读不准")
                    )
                    if let settled, (settled.item.midX < settled.divider.midX) == toStash {
                        succeeded = true
                        break
                    }
                }
                let log = "🧲 \(toStash ? "收纳" : "恢复")\(name): \(succeeded ? "成功" : "失败")"
                    + " | 起点=\(shot.map { "\(Int($0.from.x)),\(Int($0.from.y))" } ?? "?")"
                    + " 目标=\(shot.map { "\(Int($0.target.x))" } ?? "?")"
                    + " 原边界=\(shot.map { "\(Int($0.divider.midX))" } ?? "?")"
                    + " | \(tried.joined(separator: " / "))"
                DispatchQueue.main.async {
                    self.debugLog(log)
                    self.finishMove(
                        wasArranging: wasArranging,
                        bundleID: bundleID,
                        toStash: toStash,
                        message: succeeded ? nil
                            : "\(name) 挪不动：这个应用不接受合成拖拽，可点「整理」后按住 ⌘ 手动拖"
                    )
                }
            }
        }
    }

    /// 同一时刻读「图标 + 分隔符」的位置，并确认两者真的在同一条菜单栏上。
    ///
    /// 为什么非得成对读：macOS 26 给每块屏幕都留一份状态项副本，AX 每次返回哪一份并不固定。
    /// 一旦图标读到内建屏那份、分隔符读到外接屏那份，落点就会算到屏幕外去
    /// —— 实测过 图标 x=1278 配 分隔符 x=-3805，落点被夹成 x=6，
    /// 结果两种策略都只把图标推了一格（1278→1244）。
    ///
    /// 判定同屏用两条：纵向对齐（同一条菜单栏），且两个中点落在同一块显示器范围内。
    private func alignedFrames(of element: AXUIElement) -> (item: CGRect, divider: CGRect)? {
        let displays = Self.quartzDisplayBounds()
        for _ in 0..<5 {
            if let item = rawFrame(of: element), item.width >= 4,
               let divider = MenuBarSectionHider.shared.dividerAXFrame(), divider.width > 0,
               abs(item.midY - divider.midY) <= 12,
               displays.contains(where: { $0.minX <= item.midX && item.midX <= $0.maxX
                                       && $0.minX <= divider.midX && divider.midX <= $0.maxX }) {
                return (item, divider)
            }
            usleep(120_000)
        }
        return nil
    }

    /// 显示器范围（Quartz 坐标，左上原点）。用 CoreGraphics 而不是 NSScreen：
    /// 这段代码跑在后台队列上，NSScreen 只保证主线程可用。
    private static func quartzDisplayBounds() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map(CGDisplayBounds)
    }

    private func finishMoveOnMain(
        wasArranging: Bool, bundleID: String, toStash: Bool, message: String?
    ) {
        DispatchQueue.main.async {
            self.finishMove(
                wasArranging: wasArranging, bundleID: bundleID, toStash: toStash, message: message
            )
        }
    }

    private func finishMove(
        wasArranging: Bool, bundleID: String, toStash: Bool, message: String?
    ) {
        movingBundleID = nil
        lastMoveMessage = message
        if message == nil {
            saveUserPreference(for: bundleID, stashed: toStash)
        }
        if !wasArranging { MenuBarSectionHider.shared.collapse() }
        after(0.4) {
            self.refreshVisibilityNow()
            // 重新枚举完再把弹窗弹回来，用户一眼看到图标已经换栏
            self.onMoveDidEnd?()
            if self.restoringSavedPreferences {
                self.after(0.35) { self.restoreNextSavedPreference() }
            }
        }
    }

    private func ownerPID(of bundleID: String) -> pid_t? {
        NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleID }?
            .processIdentifier
    }

    /// 用户手动重新打开弹窗时清掉上一次的失败提示（移动完自动弹回来的那次不清，
    /// 否则用户根本没机会看到失败原因）。
    func clearMoveMessage() { lastMoveMessage = nil }

    // MARK: - 点击弹窗里的图标 → AXPress 唤起它自己的菜单
    /// 可见图标直接按；被收纳的图标要先把分隔符收起来让它回到可见区，
    /// 否则 macOS 会把菜单弹到屏幕外（状态项此时停在 y = -1437 那种位置）。
    func clickIcon(withBundleID bundleID: String) {
        guard pressingBundleID == nil else { return }
        let needsReveal = allIcons[bundleID]?.visibility != .visible
        guard needsReveal else {
            press(bundleID: bundleID)
            return
        }
        pressingBundleID = bundleID
        let wasArranging = isArranging
        MenuBarSectionHider.shared.expand()
        after(0.2) {
            self.refreshVisibilityNow()
            self.press(bundleID: bundleID)
            // 菜单已经弹成独立窗口，不受分隔符影响，稍后恢复隐藏
            self.after(2.0) {
                self.pressingBundleID = nil
                if !wasArranging { MenuBarSectionHider.shared.collapse() }
                self.after(0.4) { self.refreshVisibilityNow() }
            }
        }
    }

    private func press(bundleID: String) {
        guard let element = allIcons[bundleID]?.axElement else {
            activateApp(bundleID: bundleID)
            return
        }
        // 读取用的 0.15s 上限对「点击」太紧：点击是用户主动发起的单次操作，
        // 给它更宽松的上限，避免误判成失败去走 activateApp 兜底。
        AXUIElementSetMessagingTimeout(element, 2.0)
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        AXUIElementSetMessagingTimeout(element, Self.axMessagingTimeout)
        if result != .success {
            debugLog("⚠️ 菜单栏图标 AXPress 失败: \(bundleID) | code=\(result.rawValue)")
            activateApp(bundleID: bundleID)
        }
    }

    private func activateApp(bundleID: String) {
        if let running = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleID
        }) {
            running.activate(options: [.activateAllWindows])
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.open(url)
        }
    }
    // MARK: - 刷新

    /// 弹窗打开、屏幕变化等场景调用：全量枚举一次。
    func refresh() {
        DispatchQueue.main.async { [weak self] in self?.refreshNow() }
    }

    /// 全量枚举：遍历运行中的应用重建图标库。
    private func refreshNow() {
        accessibilityGranted = AXIsProcessTrusted()
        let enumerated = enumerateMenuBarIconsViaAX()
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        // AX 只返回当前活跃屏幕上那一份状态项副本，双屏切换时结果可能短暂缺失。
        // 因此按 bundleID 合并，只清理已退出的应用。
        var merged = allIcons.filter { running.contains($0.key) }
        for (bundleID, info) in enumerated {
            merged[bundleID] = carryOverIfUnknown(new: info, old: merged[bundleID])
        }
        allIcons = merged
        logSummary(enumerated: enumerated.count)
        restoreSavedPreferencesIfNeeded()
    }

    /// 轻量刷新：只重探已知元素的可见性，不遍历全部进程。
    /// 点击、整理这类高频路径走它，避免又一次 48 个进程的跨进程 AX 往返。
    private func refreshVisibilityNow() {
        accessibilityGranted = AXIsProcessTrusted()
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var merged: [String: MenuBarIconInfo] = [:]
        for (bundleID, info) in allIcons where running.contains(bundleID) {
            guard let element = info.axElement, let probe = probeFrame(of: element) else {
                merged[bundleID] = info
                continue
            }
            merged[bundleID] = MenuBarIconInfo(
                bundleID: info.bundleID,
                appName: info.appName,
                icon: info.icon,
                axElement: element,
                quartzFrame: probe.frame,
                visibility: probe.visibility
            )
        }
        allIcons = merged
    }

    /// AX 这一轮读不到位置时沿用上一轮判定，否则图标会在收纳区和镜像区之间闪。
    private func carryOverIfUnknown(
        new: MenuBarIconInfo, old: MenuBarIconInfo?
    ) -> MenuBarIconInfo {
        guard let old, new.visibility == .unknown else { return new }
        return MenuBarIconInfo(
            bundleID: new.bundleID,
            appName: new.appName,
            icon: new.icon,
            axElement: new.axElement,
            quartzFrame: old.quartzFrame,
            visibility: old.visibility
        )
    }
    // MARK: - AX 枚举

    /// 单次 AX 跨进程查询的上限。不设它就用系统默认（约 3 秒/次），
    /// 遇到不响应 AX 的进程（Safari 的 WebContent 等）会把主线程整段卡死。
    /// 实测：112 个进程无上限一轮 18887ms；加上限并只查真正的 .app 后降到 15ms。
    private static let axMessagingTimeout: Float = 0.15

    /// 只有真正的 .app 才可能拥有菜单栏状态项。
    /// XPC 服务（.xpc）、插件（.appex）等 helper 进程既不会有状态项，
    /// 又常常完全不回应 AX 请求，每个都要白等一次超时，是主线程卡顿的主要来源。
    private func canOwnMenuBarExtra(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy != .prohibited && app.bundleURL?.pathExtension == "app"
    }

    private func enumerateMenuBarIconsViaAX() -> [String: MenuBarIconInfo] {
        var result: [String: MenuBarIconInfo] = [:]

        for app in NSWorkspace.shared.runningApplications {
            guard canOwnMenuBarExtra(app), let bundleID = app.bundleIdentifier else { continue }
            // 只排除自己，其余（含 Wi-Fi/电池等系统图标）都可收纳
            if bundleID == ownBundleID || excludedSystemBundleIDs.contains(bundleID) { continue }

            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(axApp, Self.axMessagingTimeout)
            guard let extras = extrasMenuBar(of: axApp) else { continue }

            var childrenRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                extras, kAXChildrenAttribute as CFString, &childrenRef
            ) == .success, let children = childrenRef as? [AXUIElement] else { continue }

            // 每个应用只取第一个状态栏图标（v1）
            guard let item = children.first else { continue }
            AXUIElementSetMessagingTimeout(item, Self.axMessagingTimeout)
            let probe = probeFrame(of: item)
            result[bundleID] = MenuBarIconInfo(
                bundleID: bundleID,
                appName: app.localizedName ?? bundleID,
                icon: appIcon(for: bundleID, name: app.localizedName ?? bundleID),
                axElement: item,
                quartzFrame: probe?.frame ?? .zero,
                visibility: probe?.visibility ?? .unknown
            )
        }
        return result
    }

    /// AXExtrasMenuBar 优先从应用元素直接读取（HIServices 定义为应用级属性，
    /// macOS 26 上从 menuBar 子元素读会失败），失败再回退到 menuBar 元素。
    private func extrasMenuBar(of axApp: AXUIElement) -> AXUIElement? {
        if let extras = copyElement(axApp, "AXExtrasMenuBar") { return extras }
        guard let menuBar = copyElement(axApp, kAXMenuBarAttribute as String) else { return nil }
        return copyElement(menuBar, "AXExtrasMenuBar")
    }

    private func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let value = ref, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    // MARK: - 可见性判定

    /// 读状态项 frame 并分类。返回 nil 表示 AX 读取失败（超时 / 进程忙），
    /// 调用方保留上一轮判定。
    private func probeFrame(of element: AXUIElement) -> (frame: CGRect, visibility: MenuBarIconVisibility)? {
        guard let frame = rawFrame(of: element) else { return nil }
        return (frame, classify(frame))
    }

    /// 只读 frame、不做任何分类，也不碰 NSScreen —— 合成拖拽在后台队列复查位置时用它。
    func rawFrame(of element: AXUIElement) -> CGRect? {
        AXUIElementSetMessagingTimeout(element, Self.axMessagingTimeout)

        var point = CGPoint.zero
        var positionRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXPositionAttribute as CFString, &positionRef
        ) == .success, let positionValue = positionRef,
            CFGetTypeID(positionValue) == AXValueGetTypeID(),
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &point) else { return nil }

        var size = CGSize.zero
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element, kAXSizeAttribute as CFString, &sizeRef
        ) == .success, let sizeValue = sizeRef,
            CFGetTypeID(sizeValue) == AXValueGetTypeID(),
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }

        return CGRect(origin: point, size: size)
    }

    private func classify(_ frame: CGRect) -> MenuBarIconVisibility {
        guard frame.width >= 4, frame.width <= 200,
              frame.height >= 8, frame.height <= 60 else { return .notDisplayed }
        if isInVisibleMenuBar(frame) { return .visible }
        // 还停在菜单栏那一条高度上（或更高）→ 是被挤出去的，能靠收起分隔符请回来
        if isParkedAtMenuBarLevel(frame) { return .hidden }
        // 其余（典型是停在主屏底部之外）→ 应用自己没把它放上菜单栏，两栏都不显示
        return .notDisplayed
    }

    /// 被 macOS 挤出可见区的状态项会被停到菜单栏之外（实测 y = -1437，
    /// 落在所有屏幕之上），所以只要判断 frame 是否还贴在某块屏幕的菜单栏那一条上。
    /// 注意不能再按「x 必须在屏幕右侧 55%」判定：图标一多，最左边那个真的会越过中线。
    private func isInVisibleMenuBar(_ frame: CGRect) -> Bool {
        guard let screen = screenContainingQuartzPoint(
            CGPoint(x: frame.midX, y: frame.midY)
        ) else { return false }
        let screenTop = quartzFrame(for: screen).minY
        return frame.minY >= screenTop - 2
            && frame.maxY <= screenTop + NSStatusBar.system.thickness + 12
    }

    /// 被挤出可见区的状态项仍停在「菜单栏高度」上，只是横向被推到屏幕外
    /// （实测 x = -3902, y = 7），也见过整条被抬到所有屏幕上方（y = -1437）。
    /// 这两种都能靠收起分隔符请回来，所以算作已收纳；
    /// 停在主屏底部之外的那种（Figma）不算，它压根没上过菜单栏。
    private func isParkedAtMenuBarLevel(_ frame: CGRect) -> Bool {
        let tops = NSScreen.screens.map { quartzFrame(for: $0).minY }
        guard let highest = tops.min() else { return false }
        let band = NSStatusBar.system.thickness + 12
        if frame.maxY <= highest + band { return true }
        return tops.contains { abs(frame.minY - $0) <= band }
    }

    private func screenContainingQuartzPoint(_ point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { quartzFrame(for: $0).contains(point) }
    }

    /// AppKit 屏幕 frame（左下原点）转成 Quartz（主屏顶部为 0，向下为正）。
    private func quartzFrame(for screen: NSScreen) -> CGRect {
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(
            x: screen.frame.minX,
            y: primaryTop - screen.frame.maxY,
            width: screen.frame.width,
            height: screen.frame.height
        )
    }

    private func appIcon(for bundleID: String, name: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: name)
            ?? NSImage(size: NSSize(width: 18, height: 18))
    }
    // MARK: - 监听

    private func setupObservers() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.refreshNow()
        })

        // 应用启动/退出：状态项跟着增减，全量枚举一次
        observers.append(workspace.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.after(1.0) { self?.refreshNow() }
        })

        observers.append(workspace.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.after(0.5) { self?.refreshNow() }
        })

        // 睡眠唤醒后，macOS 可能重新计算状态栏位置；重新读取并校正用户明确保存过的意图。
        observers.append(workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.after(1.2) { self?.refreshNow() }
        })

        // 兜底轮询：只重探已知元素，代价很小
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler { [weak self] in self?.refreshVisibilityNow() }
        timer.resume()
        refreshTimer = timer
    }

    // MARK: - 用户收纳偏好

    private var savedStashBundleIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: savedStashBundleIDsKey) ?? [])
    }

    private var savedVisibleBundleIDs: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: savedVisibleBundleIDsKey) ?? [])
    }

    private func saveUserPreference(for bundleID: String, stashed: Bool) {
        var stashedIDs = savedStashBundleIDs
        var visibleIDs = savedVisibleBundleIDs
        if stashed {
            stashedIDs.insert(bundleID)
            visibleIDs.remove(bundleID)
        } else {
            stashedIDs.remove(bundleID)
            visibleIDs.insert(bundleID)
        }
        let defaults = UserDefaults.standard
        defaults.set(Array(stashedIDs).sorted(), forKey: savedStashBundleIDsKey)
        defaults.set(Array(visibleIDs).sorted(), forKey: savedVisibleBundleIDsKey)
        defaults.synchronize()
    }

    /// 只恢复用户明确操作过的图标，避免把单纯被刘海挤出的图标误记成用户收纳。
    private func restoreSavedPreferencesIfNeeded() {
        guard accessibilityGranted, !restoringSavedPreferences else { return }
        let savedStashed = savedStashBundleIDs
        let savedVisible = savedVisibleBundleIDs
        pendingSavedPreferenceRestores = allIcons.values
            .filter { info in
                guard info.visibility != .unknown else { return false }
                if savedStashed.contains(info.bundleID) { return info.visibility != .hidden }
                if savedVisible.contains(info.bundleID) { return info.visibility == .hidden }
                return false
            }
            .sorted { $0.appName.localizedStandardCompare($1.appName) == .orderedAscending }
            .map(\.bundleID)
        guard !pendingSavedPreferenceRestores.isEmpty else { return }
        restoringSavedPreferences = true
        restoreNextSavedPreference()
    }

    private func restoreNextSavedPreference() {
        guard !pendingSavedPreferenceRestores.isEmpty else {
            restoringSavedPreferences = false
            return
        }
        let bundleID = pendingSavedPreferenceRestores.removeFirst()
        guard let info = allIcons[bundleID] else {
            restoreNextSavedPreference()
            return
        }
        let toStash = savedStashBundleIDs.contains(bundleID)
        let alreadyCorrect = toStash ? info.visibility == .hidden : info.visibility == .visible
        if alreadyCorrect {
            after(0.05) { self.restoreNextSavedPreference() }
        } else {
            move(bundleID: bundleID, toStash: toStash)
        }
    }

    // MARK: - 诊断日志（写入 /tmp/lingdongdao-debug.log）

    private func logSummary(enumerated: Int) {
        let stashed = stashedIcons().map {
            "\($0.bundleID)@\(Int($0.quartzFrame.minX)),\(Int($0.quartzFrame.minY))"
            + "/\(Int($0.quartzFrame.width))x\(Int($0.quartzFrame.height))"
        }.joined(separator: ", ")
        let visible = visibleIcons().map(\.bundleID).joined(separator: ", ")
        let idle = allIcons.values.filter { $0.visibility == .notDisplayed }
            .map(\.bundleID).joined(separator: ", ")
        debugLog(
            "🔍 菜单栏图标: 本次枚举\(enumerated)个 库内\(allIcons.count)个 "
            + "| axTrusted=\(accessibilityGranted) 整理中=\(isArranging) "
            + "| 已收纳(\(stashedIcons().count)): \(stashed) | 可见(\(visibleIcons().count)): \(visible) "
            + "| 未上栏: \(idle.isEmpty ? "无" : idle)"
        )
    }

    private func debugLog(_ msg: String) {
        print(msg)
        let line = "\(Date()): \(msg)\n"
        let url = URL(fileURLWithPath: "/tmp/lingdongdao-debug.log")
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
