import AppKit
import CoreGraphics

// MARK: - 私有 CGS（SkyLight）桥接

/// 公开的 `CGWindowListCopyWindowInfo` 在 macOS 26 上只返回控制中心自己的状态项，
/// 第三方 App 的状态项窗口一个都拿不到（实测：layer 25 里只有控制中心和本进程）。
/// 想拿到「每个状态项 → windowID」的映射只能走私有的 `CGSGetProcessMenuBarWindowList`，
/// Ice / Bartender 这类工具走的也是这条路。windowID 是新方案的关键：
/// 有了它就能把鼠标事件直接打给某个状态项窗口，不必把真指针挪过去。
typealias CGSConnectionID = Int32

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSGetWindowCount")
func CGSGetWindowCount(
    _ cid: CGSConnectionID, _ targetCID: CGSConnectionID, _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetProcessMenuBarWindowList")
func CGSGetProcessMenuBarWindowList(
    _ cid: CGSConnectionID,
    _ targetCID: CGSConnectionID,
    _ count: Int32,
    _ list: UnsafeMutablePointer<CGWindowID>,
    _ outCount: inout Int32
) -> CGError

@_silgen_name("CGSGetScreenRectForWindow")
func CGSGetScreenRectForWindow(
    _ cid: CGSConnectionID, _ wid: CGWindowID, _ outRect: inout CGRect
) -> CGError

// MARK: - 菜单栏状态项窗口

/// 一个菜单栏状态项对应的窗口信息。frame 是 Quartz 全局坐标（左上原点），
/// 和 CGEvent 的坐标系一致，可以直接拿来构造事件。
struct MenuBarWindow {
    let windowID: CGWindowID
    let ownerPID: pid_t
    let frame: CGRect
}

enum MenuBarWindowBridge {

    /// 某个窗口当前的屏幕矩形。移动后复查位置用这个 —— 纯 CGS 调用，
    /// 不碰 NSScreen / AX，可以在后台队列安全调用。
    static func frame(of windowID: CGWindowID) -> CGRect? {
        var rect = CGRect.zero
        guard CGSGetScreenRectForWindow(CGSMainConnectionID(), windowID, &rect) == .success,
              rect.width > 0 else { return nil }
        return rect
    }

    /// 落在某个坐标上的状态项窗口 —— AX 只给坐标不给 windowID，这就是两边的桥。
    ///
    /// `maxWidth` 用来把「分隔符 / 菜单栏本体」这类超宽窗口挡掉：找图标时传默认值，
    /// 想找分隔符本身时传 `.infinity`。
    static func window(at point: CGPoint, maxWidth: CGFloat = 200) -> MenuBarWindow? {
        menuBarWindows().first {
            $0.frame.width > 0 && $0.frame.width < maxWidth
                && point.x >= $0.frame.minX && point.x <= $0.frame.maxX
                && abs(point.y - $0.frame.midY) < 40
        }
    }

    /// 当前所有菜单栏状态项窗口（含本进程自己的）。
    static func menuBarWindows() -> [MenuBarWindow] {
        let cid = CGSMainConnectionID()
        var capacity: Int32 = 0
        guard CGSGetWindowCount(cid, 0, &capacity) == .success, capacity > 0 else { return [] }

        var ids = [CGWindowID](repeating: 0, count: Int(capacity))
        var realCount: Int32 = 0
        guard CGSGetProcessMenuBarWindowList(cid, 0, capacity, &ids, &realCount) == .success,
              realCount > 0 else { return [] }
        let windowIDs = Array(ids[..<Int(realCount)])

        let owners = ownerPIDs(of: windowIDs)
        return windowIDs.compactMap { id in
            guard let pid = owners[id], let frame = frame(of: id) else { return nil }
            return MenuBarWindow(windowID: id, ownerPID: pid, frame: frame)
        }
    }

    /// windowID → 所属进程。私有 list 只给 ID，进程号还得靠公开的窗口描述接口补齐。
    /// `CGWindowListCreateDescriptionFromArray` 要的是「把 windowID 当指针位模式塞进
    /// CFArray」这种老派写法，所以这里手动装箱。
    private static func ownerPIDs(of windowIDs: [CGWindowID]) -> [CGWindowID: pid_t] {
        guard !windowIDs.isEmpty else { return [:] }
        var boxed: [UnsafeRawPointer?] = windowIDs.map { UnsafeRawPointer(bitPattern: UInt($0)) }
        guard let array = CFArrayCreate(nil, &boxed, boxed.count, nil),
              let info = CGWindowListCreateDescriptionFromArray(array) as? [[String: Any]]
        else { return [:] }

        var result: [CGWindowID: pid_t] = [:]
        for entry in info {
            guard let id = entry[kCGWindowNumber as String] as? Int,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int else { continue }
            result[CGWindowID(id)] = pid_t(pid)
        }
        return result
    }
}
