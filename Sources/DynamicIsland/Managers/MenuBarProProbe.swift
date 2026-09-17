import AppKit
import CoreGraphics

/// 「零指针位移」移动方案的实测探针。只在环境变量 `DYNAMIC_ISLAND_PRO_TEST`
/// 有值时运行，结果直接打到 stdout（用 `Contents/MacOS/DynamicIsland` 跑就能看到）。
///
/// 变量值支持：应用名子串（如 `cc-switch`）定位靶子，或留空自动挑一对相邻图标。
///
/// 判定方式很关键：状态项的坐标在多屏下会整体漂移（同一个 windowID 前后两次读，
/// 可能一次在内建屏空间、一次在外接屏空间），所以**不看绝对坐标**，
/// 只看「靶子和邻居的左右顺序有没有换过来」—— 同一时刻读两个，漂移会一起漂，顺序不受影响。
///
/// 同时记录真实指针的位移：这次实验的全部意义就是「图标动了、指针没动」。
enum MenuBarProProbe {

    /// 一个可辨识的状态项：AX 元素给实时坐标，CGS windowID 给事件注解。
    private struct Item {
        let name: String
        let element: AXUIElement
        let windowID: CGWindowID
        let ownerPID: pid_t
        let appPID: pid_t?
    }

    static func runIfRequested() {
        guard let hint = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_PRO_TEST"] else { return }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 2.0) {
            run(hint: hint)
        }
    }

    // MARK: - 主流程

    private static func run(hint: String) {
        log("辅助功能权限: \(AXIsProcessTrusted() ? "有" : "无（合成事件基本都会失败）")")
        if hint.hasPrefix("geom") {
            runGeometryDump(name: String(hint.dropFirst(4)).trimmingCharacters(in: [":"]))
            return
        }
        if hint.hasPrefix("stash:") {
            runStashTest(name: String(hint.dropFirst(6)))
            return
        }
        let items = alignedItems()
        log("=== 可辨识的状态项（按当前 x 排序）===")
        for item in items {
            let x = frame(of: item).map { Int($0.minX) } ?? -1
            log(String(format: "  x=%5d wid=%-7d owner=%-5d app=%-5d %@",
                       x, Int(item.windowID), Int(item.ownerPID),
                       Int(item.appPID ?? -1), item.name))
        }

        guard let (target, neighbor) = pickPair(items, hint: hint) else {
            log("❌ 没挑出可测的一对（hint=\"\(hint)\"，需要至少两个能被 AX 认出来的第三方图标）")
            return
        }
        log("靶子=\(target.name)（wid \(target.windowID)）｜邻居=\(neighbor.name)（wid \(neighbor.windowID)）")

        guard let initial = order(target, neighbor) else { log("❌ 读不到初始顺序"); return }
        log("初始顺序: \(initial == .left ? "靶子在左" : "靶子在右")")

        for (index, recipe) in recipes(target: target, neighbor: neighbor).enumerated() {
            attempt(no: index + 1, recipe: recipe, target: target, neighbor: neighbor)
        }

        // 收尾：不管测出什么，把菜单栏恢复成测试前的顺序。
        if order(target, neighbor) != initial {
            log("恢复原始顺序（用线上方案，指针会跳一下）")
            attempt(no: 0, recipe: controlRecipe, target: target, neighbor: neighbor)
        }
        log("=== 结束 ===")
    }

    // MARK: - 单次尝试

    private enum Order { case left, right }

    /// 发一次事件序列，然后看顺序换没换、指针动没动。
    ///
    /// 每次尝试都是「把靶子挪到邻居的另一边」，所以成功一次方向就翻一次，
    /// 不需要额外的复位步骤：下一个配方自然会往回挪。
    private static func attempt(no: Int, recipe: MenuBarItemMoverPro.Recipe, target: Item, neighbor: Item) {
        guard let before = order(target, neighbor),
              let targetFrame = frame(of: target), let neighborFrame = frame(of: neighbor) else {
            log("配方 #\(no) [\(recipe)] → ❌ 读不到坐标，跳过")
            return
        }
        let itemWindow = MenuBarWindow(windowID: target.windowID, ownerPID: target.ownerPID, frame: targetFrame)
        let anchorWindow = MenuBarWindow(windowID: neighbor.windowID, ownerPID: neighbor.ownerPID, frame: neighborFrame)
        let destination: MenuBarItemMoverPro.Destination =
            before == .right ? .leftOf(anchorWindow) : .rightOf(anchorWindow)

        // 每次尝试前把指针放回屏幕中间，这样各配方的位移数字才可比
        // （否则上一条配方把指针留在菜单栏，下一条的位移看起来就很小）。
        parkCursor()
        let cursorBefore = cursor()
        let start = Date()
        let report = MenuBarItemMoverPro.perform(itemWindow, to: destination, recipe: recipe)
        // 指针位移是**异步**发生的：事件 post 完立刻读还是原地，几十毫秒后才被挪走。
        // 所以这里持续采样 300ms，取离出发点最远的那次，并记下当时的坐标 ——
        // 落在菜单栏那条高度（y < 40）说明是事件带跑的，落在屏幕中间说明是真人在动鼠标。
        var peak: CGFloat = 0
        var peakPoint = cursorBefore
        for _ in 0..<30 {
            usleep(10_000)
            let now = cursor()
            let drift = hypot(now.x - cursorBefore.x, now.y - cursorBefore.y)
            if drift > peak { peak = drift; peakPoint = now }
        }
        usleep(150_000)                                     // 给菜单栏一点时间重排
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        let cursorAfter = cursor()
        let drift = hypot(cursorAfter.x - cursorBefore.x, cursorAfter.y - cursorBefore.y)
        let after = order(target, neighbor)

        let verdict = after == nil ? "❓ 读不到结果" : (after != before ? "✅ 顺序换了" : "❌ 没动")
        log("配方 #\(no) [\(recipe)] → \(verdict)"
            + String(format: "｜峰值 %.0fpx@(%.0f,%.0f)｜结束 %.0fpx@(%.0f,%.0f)｜耗时 %dms",
                     peak, peakPoint.x, peakPoint.y, drift, cursorAfter.x, cursorAfter.y, elapsed))
        log("    发送: \(report.log)")
    }

    /// 线上正在用的方案：完整 ⌘ 拖拽 + HID 投递 + 指针跟随。既是对照组也是复位手段。
    private static let controlRecipe = MenuBarItemMoverPro.Recipe(
        annotate: false, fullDrag: true, startAtItem: true, warpCursor: true, delivery: .hid
    )

    /// 第六轮：第五轮已经证明「不复位就等于把用户的指针留在菜单栏上」
    /// （#2/#3/#5 三个不碰指针的配方，指针全部停在抬起坐标、y=20），
    /// 所以隐藏 + 复位必须留着。这一轮只验一件事：复位改成有条件之后
    /// （只在指针确实停在落点附近时才 warp 回去），线上配方还是 0px。
    private static func recipes(target: Item, neighbor: Item) -> [MenuBarItemMoverPro.Recipe] {
        [
            controlRecipe,
            MenuBarItemMoverPro.invisibleQuick,
            MenuBarItemMoverPro.invisibleQuick,
            controlRecipe,
        ]
    }

    // MARK: - 几何诊断：分隔符和图标到底在不在同一个坐标空间

    /// `DYNAMIC_ISLAND_PRO_TEST=geom:FlClash` —— 把落点计算依赖的所有数一次读出来：
    /// 屏幕布局、分隔符的 AppKit 窗口坐标、分隔符的 AX 坐标、所有图标的 AX 坐标。
    /// 用来定位「目标=6 原边界=-3805」那次失败到底是哪一步串了坐标空间。
    private static func runGeometryDump(name: String) {
        let hider = MenuBarSectionHider.shared
        let manager = MenuBarIconManager.shared
        for screen in DispatchQueue.main.sync(execute: { NSScreen.screens }) {
            log("屏幕 \(rect(screen.frame))｜刘海=\(screen.safeAreaInsets.top > 0)")
        }
        for expanded in [true, false] {
            DispatchQueue.main.async { expanded ? hider.expand() : hider.collapse() }
            usleep(800_000)
            log("—— 分隔符\(expanded ? "整理态（窄条）" : "隐藏态（超长）") ——")
            let appKitFrame = DispatchQueue.main.sync { hider.dividerQuartzFrame() }
            log("  AppKit 窗口 → \(appKitFrame.map(rect) ?? "读不到（宽度不在 0..<200）")")
            // AX 查自己必须在后台线程发：请求要由主线程应答，在主线程上问会互等。
            for item in hider.ownStatusItems() {
                log("  自家状态项 id=\"\(item.identifier)\" title=\"\(item.title)\" → \(rect(item.frame))")
            }
            log("  AX 认定的分隔符 → \(hider.dividerAXFrame().map(rect) ?? "读不到")")
            let rows = manager.allIcons.values
                .compactMap { info -> (String, CGRect)? in
                    guard let element = info.axElement,
                          let frame = manager.rawFrame(of: element) else { return nil }
                    return (info.appName, frame)
                }
                .sorted { $0.1.minX < $1.1.minX }
            for (appName, frame) in rows {
                let isTarget = !name.isEmpty && appName.localizedCaseInsensitiveContains(name)
                log("  图标 \(rect(frame)) \(appName)\(isTarget ? "  ← 靶子" : "")")
            }
        }
        log("=== 几何诊断结束 ===")
    }

    private static func rect(_ r: CGRect) -> String {
        String(format: "x=%5.0f..%-5.0f y=%4.0f h=%2.0f", r.minX, r.maxX, r.minY, r.height)
    }

    // MARK: - 端到端：真的走一遍收纳 / 恢复

    /// `DYNAMIC_ISLAND_PRO_TEST=stash:微信` —— 走 `MenuBarIconManager` 的真实收纳链路
    /// （关弹窗 → 展开分隔符 → 移动 → 复查 → 收起），全程盯着指针有没有跳。
    private static func runStashTest(name: String) {
        let manager = MenuBarIconManager.shared
        guard let info = manager.allIcons.values
            .first(where: { $0.appName.localizedCaseInsensitiveContains(name) }) else {
            log("❌ 菜单栏里没找到「\(name)」")
            return
        }
        log("端到端：\(info.appName)（\(info.bundleID)）")
        parkCursor()

        for stashing in [true, false] {
            let label = stashing ? "收纳" : "恢复"
            let before = cursor()
            DispatchQueue.main.async {
                stashing ? manager.stash(bundleID: info.bundleID)
                         : manager.unstash(bundleID: info.bundleID)
            }
            // 整条链路大约 1.5s；采样 3s，看指针有没有在任何时刻离开过原地。
            // 关键是分开两个数：
            // - 峰值：包括「指针被藏起来的那 150ms」，一定会看到它到落点去了一趟；
            // - 可见峰值：只统计指针真的画在屏幕上的采样 —— 这才是用户眼睛能看到的位移。
            var peak: CGFloat = 0
            var peakPoint = before
            var visiblePeak: CGFloat = 0
            var visiblePeakPoint = before
            for _ in 0..<300 {
                usleep(10_000)
                let now = cursor()
                let drift = hypot(now.x - before.x, now.y - before.y)
                if drift > peak { peak = drift; peakPoint = now }
                if !MenuBarItemMoverPro.isCursorHidden, drift > visiblePeak {
                    visiblePeak = drift
                    visiblePeakPoint = now
                }
            }
            let after = cursor()
            log(String(format:
                "%@ 结束｜起点(%.0f,%.0f) 峰值%.0fpx@(%.0f,%.0f) 可见峰值%.0fpx@(%.0f,%.0f) 结束(%.0f,%.0f)｜提示=%@",
                label, before.x, before.y, peak, peakPoint.x, peakPoint.y,
                visiblePeak, visiblePeakPoint.x, visiblePeakPoint.y,
                after.x, after.y, manager.lastMoveMessage ?? "无"))
        }
        log("=== 端到端结束 ===")
    }

    // MARK: - AX ⨯ CGS 对齐

    /// 把「AX 认识的图标」和「CGS 的状态项窗口」对上。
    ///
    /// macOS 26 实测：CGS 把所有状态项窗口都算在控制中心名下，`kCGWindowOwnerPID`
    /// 拿不到真正归属；反过来 AX 只给坐标不给 windowID。两边靠坐标包含关系配对。
    private static func alignedItems() -> [Item] {
        let manager = MenuBarIconManager.shared
        let windows = MenuBarWindowBridge.menuBarWindows().filter { $0.frame.width > 0 && $0.frame.width < 200 }
        var items: [Item] = []
        for info in manager.allIcons.values {
            guard let element = info.axElement, let axFrame = manager.rawFrame(of: element),
                  axFrame.width > 0 else { continue }
            guard let window = windows.first(where: {
                axFrame.midX >= $0.frame.minX && axFrame.midX <= $0.frame.maxX
                    && abs(axFrame.midY - $0.frame.midY) < 40
            }) else { continue }
            let appPID = NSRunningApplication
                .runningApplications(withBundleIdentifier: info.bundleID).first?.processIdentifier
            items.append(Item(name: info.appName, element: element, windowID: window.windowID,
                              ownerPID: window.ownerPID, appPID: appPID))
        }
        return items.sorted { (frame(of: $0)?.minX ?? 0) < (frame(of: $1)?.minX ?? 0) }
    }

    /// 挑「靶子 + 相邻的邻居」，两个都得在可见区（x > 0）。
    private static func pickPair(_ items: [Item], hint: String) -> (target: Item, neighbor: Item)? {
        let visible = items.filter { (frame(of: $0)?.minX ?? -1) > 0 }
        guard visible.count >= 2 else { return nil }
        if !hint.isEmpty, hint != "auto",
           let index = visible.firstIndex(where: { $0.name.localizedCaseInsensitiveContains(hint) }) {
            return (visible[index], index > 0 ? visible[index - 1] : visible[index + 1])
        }
        return (visible[1], visible[0])
    }

    // MARK: - 读数

    private static func frame(of item: Item) -> CGRect? {
        MenuBarIconManager.shared.rawFrame(of: item.element)
    }

    /// 靶子相对邻居在左还是在右。两个坐标在同一时刻读，多屏坐标漂移会一起漂，不影响顺序。
    private static func order(_ target: Item, _ neighbor: Item) -> Order? {
        guard let t = frame(of: target), let n = frame(of: neighbor) else { return nil }
        return t.minX < n.minX ? .left : .right
    }

    private static func cursor() -> CGPoint {
        MenuBarItemMoverPro.cursorLocation()
    }

    /// 把指针挪到「离菜单栏很远」的地方（主屏中心），作为每次尝试的统一起点。
    private static func parkCursor() {
        let bounds = CGDisplayBounds(CGMainDisplayID())
        CGWarpMouseCursorPosition(CGPoint(x: bounds.midX, y: bounds.midY))
        usleep(60_000)
    }

    private static func log(_ message: String) {
        print("[ProProbe] \(message)")
        fflush(stdout)
    }
}
