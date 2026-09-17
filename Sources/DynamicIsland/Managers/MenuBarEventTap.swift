import CoreGraphics
import Foundation

/// 一个轻量的 `CGEventTap` 包装。
///
/// 新的移动方案（`MenuBarItemMoverPro`）需要「在某个 tap 的回调里再 post 事件」这种
/// 套娃写法（Ice 管它叫 scromble），所以必须能随手开关一个 tap，并且能确认
/// 自己发出去的事件真的回流了。系统 API 是 CFMachPort + run loop source，
/// 这里包一层，让调用方只面对 `enable()` / `disable()`。
///
/// 注意：tap 挂在**创建它的那条线程**的 run loop 上，回调只有在那条线程的
/// run loop 被泵动时才会触发。调用方负责泵（见 `MenuBarItemMoverPro.pump`）。
final class MenuBarEventTap {

    /// 事件投递/监听位置，和 `CGEventTapLocation` 一一对应，外加「某个进程」。
    enum Location {
        case hid
        case session
        case annotatedSession
        case pid(pid_t)

        var label: String {
            switch self {
            case .hid: return "hidTap"
            case .session: return "sessionTap"
            case .annotatedSession: return "annotatedSessionTap"
            case .pid(let pid): return "pid(\(pid))"
            }
        }
    }

    /// 回调：返回 nil 吞掉事件，返回事件本身放它过去。
    typealias Handler = (MenuBarEventTap, CGEventType, CGEvent) -> Unmanaged<CGEvent>?

    let label: String
    private let location: Location
    private let options: CGEventTapOptions
    private let mask: CGEventMask
    private let handler: Handler

    private var machPort: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var selfRetain: Unmanaged<MenuBarEventTap>?

    private(set) var isEnabled = false

    init(
        label: String, location: Location, options: CGEventTapOptions,
        types: [CGEventType], handler: @escaping Handler
    ) {
        self.label = label
        self.location = location
        self.options = options
        self.mask = types.reduce(into: CGEventMask(0)) { $0 |= CGEventMask(1) << CGEventMask($1.rawValue) }
        self.handler = handler
    }

    deinit { disable() }

    /// 在当前线程的 run loop 上装好 tap。失败通常意味着没有辅助功能权限。
    @discardableResult
    func enable() -> Bool {
        guard machPort == nil else { return true }
        let info = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<MenuBarEventTap>.fromOpaque(info).takeUnretainedValue()
            return tap.handler(tap, type, event)
        }

        let port: CFMachPort?
        switch location {
        case .pid(let pid):
            port = CGEvent.tapCreateForPid(
                pid: pid, place: .tailAppendEventTap, options: options,
                eventsOfInterest: mask, callback: callback, userInfo: info
            )
        case .hid, .session, .annotatedSession:
            port = CGEvent.tapCreate(
                tap: cgLocation, place: .tailAppendEventTap, options: options,
                eventsOfInterest: mask, callback: callback, userInfo: info
            )
        }
        guard let port, let source = CFMachPortCreateRunLoopSource(nil, port, 0) else { return false }

        let runLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(runLoop, source, .defaultMode)
        CGEvent.tapEnable(tap: port, enable: true)

        self.machPort = port
        self.source = source
        self.runLoop = runLoop
        self.selfRetain = Unmanaged.passRetained(self)
        self.isEnabled = true
        return true
    }

    /// 系统偶尔会因为超时/用户输入把 tap 关掉，回调里收到对应事件时用这个拉起来。
    func reenable() {
        guard let machPort else { return }
        CGEvent.tapEnable(tap: machPort, enable: true)
        isEnabled = true
    }

    func disable() {
        guard let machPort else { return }
        CGEvent.tapEnable(tap: machPort, enable: false)
        if let source, let runLoop {
            CFRunLoopRemoveSource(runLoop, source, .defaultMode)
        }
        CFMachPortInvalidate(machPort)
        self.machPort = nil
        self.source = nil
        self.runLoop = nil
        isEnabled = false
        selfRetain?.release()
        selfRetain = nil
    }

    private var cgLocation: CGEventTapLocation {
        switch location {
        case .hid: return .cghidEventTap
        case .annotatedSession: return .cgAnnotatedSessionEventTap
        case .session, .pid: return .cgSessionEventTap
        }
    }
}
