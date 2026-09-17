import AppKit
import CoreGraphics

/// 合成菜单栏状态项拖拽的「实验台」：同一套坐标，多种事件配方，逐个试。
///
/// 背景：真正把图标挪动的只有「按住 ⌘ 横向拖拽」这一套鼠标事件。问题在于
/// 投递方式 —— 往 HID / session tap 打位置事件，真实指针会跟着跑（用户会看到跳）。
/// Ice 的做法是给事件写上目标状态项的 windowID，让命中测试认字段不认指针：
///
/// - `.mouseEventWindowUnderMousePointer`
/// - `.mouseEventWindowUnderMousePointerThatCanHandleThisEvent`
/// - `CGEventField(rawValue: 0x33)`（未公开的 windowID 字段）
/// - `.eventTargetUnixProcessID` 收事件的进程
///
/// macOS 26 上状态项窗口全部归控制中心（CGS 列表里 owner 一律是它），
/// 所以「发给谁」也是一个要试的维度。哪种配方真的有效由 `MenuBarProProbe` 实测。
enum MenuBarItemMoverPro {

    /// 落点：贴到目标状态项的左边还是右边。
    enum Destination {
        case leftOf(MenuBarWindow)
        case rightOf(MenuBarWindow)

        var anchor: MenuBarWindow {
            switch self {
            case .leftOf(let window), .rightOf(let window): return window
            }
        }

        /// 抬起事件的坐标：贴左边落在落点窗口左沿，贴右边落在右沿。
        func endPoint(using frame: CGRect) -> CGPoint {
            switch self {
            case .leftOf: return CGPoint(x: frame.minX, y: frame.midY)
            case .rightOf: return CGPoint(x: frame.maxX, y: frame.midY)
            }
        }
    }

    /// 事件投递位置。
    enum Delivery: String {
        case session
        case annotatedSession
        case hid
        /// 直接发给某个进程，不进全局事件流 —— 真实指针不会动。
        case toPid
        /// Ice 的「scromble」：借目标进程的 tap 回调把事件 post 到 session tap。
        case scromble
    }

    /// 一次尝试的配方。各维度可以自由组合，方便做矩阵实测。
    struct Recipe: CustomStringConvertible {
        /// 是否写 windowID 那几个字段（Ice 的核心技巧）。
        var annotate = true
        /// true = 完整合成 ⌘ 拖拽（移动/按下/拖动×2/抬起 + 命令键）；
        /// false = Ice 的极简两连（只有 ⌘ 按下 + 抬起）。
        var fullDrag = false
        /// 起点用图标的真实坐标，还是屏幕外的 (20000, 20000)。
        var startAtItem = false
        /// 起点直接用「指针现在所在的位置」——事件位置不变，指针就没有理由动。
        /// 只有当命中测试真的只认 windowID 字段时，这样才还能选中图标。
        var startAtCursor = false
        /// 落点也用指针当前位置：如果连方向都能靠注解表达，那就是彻底零位移。
        var endAtCursor = false
        /// 对照组用：把真实指针跟着事件挪（线上方案就是这么干的）。
        var warpCursor = false
        /// 实测发现：能让图标动的投递方式（session/hid）事件本身就会把指针拖走。
        /// 这个开关在发事件期间调用 `CGAssociateMouseAndMouseCursorPosition(false)`，
        /// 看能不能把「事件位置」和「指针位置」解绑 —— 这是唯一有希望做到真正零位移的路。
        var decoupleCursor = false
        /// 退路：解绑不管用时，至少让位移看不见（隐藏指针 → 拖 → 复位 → 显示）。
        var hideCursor = false
        /// 序列结束后把指针 warp 回出发点。
        var restoreCursor = false
        var delivery: Delivery = .session
        /// 事件的目标进程；nil 表示用窗口自己的 owner。
        var pidOverride: pid_t?

        var description: String {
            var parts = [delivery.rawValue]
            parts.append(fullDrag ? "完整拖拽" : "两连")
            if annotate { parts.append("带windowID") }
            if startAtItem { parts.append("起点在图标上") }
            if startAtCursor { parts.append("起点=指针处") }
            if endAtCursor { parts.append("落点=指针处") }
            if warpCursor { parts.append("指针跟随") }
            if decoupleCursor { parts.append("解绑指针") }
            if hideCursor { parts.append("隐藏指针") }
            if restoreCursor { parts.append("复位指针") }
            if let pidOverride { parts.append("pid=\(pidOverride)") }
            return parts.joined(separator: "+")
        }
    }

    /// 一次尝试发了什么、指针被带跑了多远（峰值，采样自每个事件之后）。
    struct Report {
        var log = ""
        var peakDrift: CGFloat = 0
    }

    /// 屏幕外起点：命中测试如果认 windowID 字段，坐标写哪儿都无所谓（Ice 的做法）。
    private static let offscreenStart = CGPoint(x: 20_000, y: 20_000)

    /// 实测胜出的配方（`MenuBarProProbe` 第四、五轮，各 6/6 成功）：
    /// 只发两个事件，起点写图标自己的坐标，落点写真实目标坐标，全程隐藏指针、结束复位。
    ///
    /// 为什么落点必须是真坐标：实测把抬起事件写在指针当前位置（靠注解表达方向），
    /// 图标一次都没动 —— macOS 26 用抬起事件的**位置**决定插到哪儿，注解只负责「抓住谁」。
    /// 所以指针物理上一定会被带到落点去（第五轮不复位的三个配方，指针全部停在
    /// 抬起坐标、y=20 的菜单栏高度上），只能靠「隐藏 + 复位」让它在视觉上完全无感。
    static let invisibleQuick = Recipe(
        annotate: true, fullDrag: false, startAtItem: true,
        hideCursor: true, restoreCursor: true, delivery: .session
    )

    /// 生产入口：把某个状态项挪到指定坐标，指针看不见地过去再回来。
    ///
    /// - Parameters:
    ///   - itemFrame: 图标现在的位置（AX 读出来的 Quartz 坐标）。
    ///   - itemWindowID: 图标的状态项窗口；写进事件让命中测试抓住它。
    ///   - target: 落点坐标 —— 收纳时是分隔符左侧一点，恢复时是右侧一点。
    ///   - targetWindowID: 落点处的窗口（一般是分隔符自己），拿不到就退回用图标自己的。
    static func move(
        itemFrame: CGRect, itemWindowID: CGWindowID, pid: pid_t,
        to target: CGPoint, targetWindowID: CGWindowID?
    ) -> Report {
        let item = MenuBarWindow(windowID: itemWindowID, ownerPID: pid, frame: itemFrame)
        // 宽度为 0 的落点矩形：minX == maxX == 目标 x，leftOf / rightOf 都落在同一点。
        let anchor = MenuBarWindow(
            windowID: targetWindowID ?? itemWindowID, ownerPID: pid,
            frame: CGRect(x: target.x, y: target.y, width: 0, height: 0)
        )
        return perform(item, to: .leftOf(anchor), recipe: invisibleQuick)
    }

    /// 按配方发一次「把 item 挪到 destination」的事件序列。
    ///
    /// 只负责发事件，不判断有没有成功 —— 状态项坐标在多屏下会整体漂移，
    /// 判定交给 `MenuBarProProbe`（用 AX 的相对顺序判，不看绝对坐标）。
    /// 返回值是发了什么的可读记录。
    @discardableResult
    static func perform(_ item: MenuBarWindow, to destination: Destination, recipe: Recipe) -> Report {
        let anchor = destination.anchor
        let pid = recipe.pidOverride ?? item.ownerPID
        let here = cursorLocation()
        let end = recipe.endAtCursor ? here : destination.endPoint(using: anchor.frame)
        let start: CGPoint
        if recipe.startAtCursor {
            start = here
        } else if recipe.startAtItem {
            start = CGPoint(x: item.frame.midX, y: item.frame.midY)
        } else {
            start = offscreenStart
        }

        guard let source = permitAllEvents() else { return Report(log: "❌ 建不出 CGEventSource") }
        var report = Report()
        var sent: [String] = []
        let origin = here

        // 指针相关的开关。全部用 defer 兜底，中途 return 也一定还原 ——
        // 解绑状态残留会让用户的鼠标看起来卡死。
        if recipe.hideCursor { CGDisplayHideCursor(CGMainDisplayID()); isCursorHidden = true }
        defer { if recipe.hideCursor { CGDisplayShowCursor(CGMainDisplayID()); isCursorHidden = false } }
        if recipe.decoupleCursor { CGAssociateMouseAndMouseCursorPosition(0) }
        defer { if recipe.decoupleCursor { CGAssociateMouseAndMouseCursorPosition(1) } }
        // defer 是后进先出：复位先跑，跑完才重新显示指针，所以位移全程看不见。
        defer {
            // 只有「指针确实被我们带到落点了」才复位。实测（第五轮 #2/#3/#5）
            // 这套事件会把指针拖到抬起事件那个坐标去，y 落在菜单栏那条高度上；
            // 但万一此刻指针在别处，那就是用户自己在动鼠标 ——
            // 这种时候硬 warp 回原位才是真的在抢他的鼠标。
            if recipe.restoreCursor {
                let now = cursorLocation()
                if hypot(now.x - end.x, now.y - end.y) < 60 {
                    CGWarpMouseCursorPosition(origin)
                }
            }
        }

        func send(_ type: CGEventType, at point: CGPoint, window: CGWindowID, flags: CGEventFlags) {
            guard let event = makeEvent(type: type, at: point, source: source) else { return }
            event.flags = flags
            if recipe.annotate { annotate(event, window: window, pid: pid) }
            if recipe.warpCursor { CGWarpMouseCursorPosition(point) }
            post(event, recipe: recipe, pid: pid)
            let now = cursorLocation()
            report.peakDrift = max(report.peakDrift, hypot(now.x - origin.x, now.y - origin.y))
            sent.append("\(name(of: type))@\(Int(point.x))")
        }

        if recipe.fullDrag {
            postCommandKey(down: true, source: source, recipe: recipe, pid: pid)
            send(.mouseMoved, at: start, window: item.windowID, flags: .maskCommand)
            pause(16)
            send(.leftMouseDown, at: start, window: item.windowID, flags: .maskCommand)
            pause(70)
            let nudge = CGPoint(x: start.x + (end.x > start.x ? 6 : -6), y: start.y)
            send(.leftMouseDragged, at: nudge, window: item.windowID, flags: .maskCommand)
            pause(20)
            send(.leftMouseDragged, at: end, window: anchor.windowID, flags: .maskCommand)
            pause(50)
            send(.leftMouseUp, at: end, window: anchor.windowID, flags: .maskCommand)
            pause(30)
            postCommandKey(down: false, source: source, recipe: recipe, pid: pid)
        } else {
            // Ice 原味：只有 ⌘ 按下 + 抬起，中间什么都不发。
            send(.leftMouseDown, at: start, window: item.windowID, flags: .maskCommand)
            pause(50)
            send(.leftMouseUp, at: end, window: anchor.windowID, flags: [])
            pause(50)
        }
        report.log = sent.joined(separator: " → ")
        return report
    }

    static func cursorLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    /// 指针此刻是否被我们藏着。`CGCursorIsVisible()` 在当前 SDK 已经不可用，
    /// 而「用户眼睛看得见的位移」是这套方案唯一要紧的指标，所以自己记一个标记：
    /// 探针据此把「藏起来那 150ms 的位移」和「可见位移」分开统计。
    private(set) static var isCursorHidden = false

    // MARK: - 事件构造

    /// 合成事件默认会被系统「抑制」一小段时间（避免和真人输入打架），
    /// 这里把抑制窗口清零，并允许本地鼠标/键盘事件照常通过。
    private static func permitAllEvents() -> CGEventSource? {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return nil }
        for state in [CGEventSuppressionState.eventSuppressionStateRemoteMouseDrag,
                      .eventSuppressionStateSuppressionInterval] {
            source.setLocalEventsFilterDuringSuppressionState(
                [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents],
                state: state
            )
        }
        source.localEventsSuppressionInterval = 0
        return source
    }

    private static func makeEvent(type: CGEventType, at point: CGPoint, source: CGEventSource) -> CGEvent? {
        CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
    }

    /// Ice 的核心技巧：把「指针底下是哪个窗口」直接写进事件字段。
    /// 命中测试如果读这些字段，事件就会落到指定状态项上，真实指针不用动。
    private static func annotate(_ event: CGEvent, window: CGWindowID, pid: pid_t) {
        let value = Int64(window)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: value)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: value)
        if let windowIDField = CGEventField(rawValue: 0x33) {
            event.setIntegerValueField(windowIDField, value: value)
        }
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(pid))
    }

    private static func name(of type: CGEventType) -> String {
        switch type {
        case .mouseMoved: return "移动"
        case .leftMouseDown: return "按下"
        case .leftMouseDragged: return "拖动"
        case .leftMouseUp: return "抬起"
        default: return "事件\(type.rawValue)"
        }
    }

    private static func pause(_ milliseconds: UInt32) {
        usleep(milliseconds * 1000)
    }

    // MARK: - 投递

    private static func post(_ event: CGEvent, recipe: Recipe, pid: pid_t) {
        switch recipe.delivery {
        case .session: event.post(tap: .cgSessionEventTap)
        case .annotatedSession: event.post(tap: .cgAnnotatedSessionEventTap)
        case .hid: event.post(tap: .cghidEventTap)
        case .toPid: event.postToPid(pid)
        case .scromble: scromble(event, pid: pid)
        }
    }

    /// ⌘ 也得真按下去：只给鼠标事件挂 `.maskCommand` 有时不算「按住了修饰键」。
    private static func postCommandKey(down: Bool, source: CGEventSource, recipe: Recipe, pid: pid_t) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: down) else { return }
        event.flags = down ? .maskCommand : []
        switch recipe.delivery {
        case .toPid, .scromble: event.postToPid(pid)
        case .session: event.post(tap: .cgSessionEventTap)
        case .annotatedSession: event.post(tap: .cgAnnotatedSessionEventTap)
        case .hid: event.post(tap: .cghidEventTap)
        }
        pause(10)
    }

    /// Ice 的「scromble」：先往目标进程扔一个打了标记的空事件，
    /// 在自己给那个进程装的 tap 回调里再把真事件 post 到 session tap ——
    /// 这样事件是「从目标进程的上下文里」发出去的。
    private static func scromble(_ event: CGEvent, pid: pid_t) {
        guard let source = permitAllEvents(), let trigger = CGEvent(source: source) else { return }
        let tag = nextTag()
        trigger.setIntegerValueField(.eventSourceUserData, value: tag)

        var didPost = false
        let tap = MenuBarEventTap(
            label: "scromble", location: .pid(pid), options: .defaultTap, types: [.null]
        ) { tap, type, incoming in
            switch type {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                tap.reenable()
                return Unmanaged.passUnretained(incoming)
            default: break
            }
            guard incoming.getIntegerValueField(.eventSourceUserData) == tag else {
                return Unmanaged.passUnretained(incoming)
            }
            event.post(tap: .cgSessionEventTap)
            didPost = true
            return nil        // 吞掉这个信号事件，别让它流出去
        }
        guard tap.enable() else { return }
        defer { tap.disable() }
        trigger.postToPid(pid)
        pump(until: { didPost }, timeout: 0.2)
    }

    /// tap 的回调挂在当前线程的 run loop 上，不泵就永远不会触发。
    private static func pump(until condition: () -> Bool, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.005, true)
        }
    }

    private static var tagCounter: Int64 = 0x1D_0000

    private static func nextTag() -> Int64 {
        tagCounter += 1
        return tagCounter
    }
}
