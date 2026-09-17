import AppKit
import ApplicationServices

/// 把「别的应用」的菜单栏状态项挪到收纳边界的左边或右边。
///
/// macOS 没有任何公开 API 能移动别人的状态项，唯一的办法是把用户手动会做的那套
/// 「按住 ⌘ 横向拖拽」鼠标事件原样合成一遍。两种投递方式都实现了：
///
/// 1. `postToPid`：事件只发给状态项所属进程，用户的真实指针一动不动。
///    实测**无效** —— 图标 frame 一点没动，重排的命中测试显然认真实指针位置。
/// 2. HID tap + 真实指针跟着走：全局投递，指针会跳过去再跳回来，实测有效。
///
/// 所以默认只跑 `hidTap`（见 `Delivery.attemptOrder`）。
/// 每次移动都由调用方复查 frame 是否真的换了边 —— 注意要拿**移动之后**的
/// 分隔符位置做参照，图标换边会让整条菜单栏重排。
enum MenuBarItemMover {

    enum Delivery: String {
        /// 只发给目标进程，不动真实指针
        case toProcess
        /// 全局 HID 投递，期间把真实指针挪到拖拽路径上，结束后放回原处
        case hidTap

        /// 实际使用的顺序。`toProcess` 投给图标所属 App 实测完全不生效
        /// （两次尝试图标 frame 一点没变），所以只留 `hidTap`；
        /// 保留另一个 case 是为了排查时能一键切回去对比。
        static let attemptOrder: [Delivery] = [.hidTap]
    }

    /// 合成一次 ⌘ 拖拽：从 start 拖到 end（都是 Quartz 全局坐标，左上原点）。
    /// 必须在后台队列调用 —— 中间有几百毫秒的节拍等待，放主线程会卡住 UI。
    static func commandDrag(
        from start: CGPoint,
        to end: CGPoint,
        ownerPID: pid_t,
        delivery: Delivery
    ) {
        let source = CGEventSource(stateID: .hidSystemState)
        let restorePoint = currentCursorQuartzPoint()

        func post(_ type: CGEventType, _ point: CGPoint) {
            guard let event = CGEvent(
                mouseEventSource: source,
                mouseType: type,
                mouseCursorPosition: point,
                mouseButton: .left
            ) else { return }
            event.flags = .maskCommand
            switch delivery {
            case .toProcess:
                event.postToPid(ownerPID)
            case .hidTap:
                // 有些命中测试看的是真实指针位置，所以这里让指针跟着事件走
                CGWarpMouseCursorPosition(point)
                event.post(tap: .cghidEventTap)
            }
        }

        // ⌘ 按下：状态项的重排逻辑要看到 command 修饰键
        postCommandKey(source: source, down: true, ownerPID: ownerPID, delivery: delivery)
        post(.mouseMoved, start)
        pause(16)
        post(.leftMouseDown, start)
        pause(70)

        // 先小幅抖一下越过拖拽阈值，再一步拖到目标 —— 指针从起点到终点
        // 只跳两下，几百毫秒内完成，用户几乎察觉不到
        post(.leftMouseDragged, CGPoint(x: start.x + (end.x > start.x ? 6 : -6), y: start.y))
        pause(20)
        post(.leftMouseDragged, end)
        pause(50)
        post(.leftMouseUp, end)
        pause(30)
        postCommandKey(source: source, down: false, ownerPID: ownerPID, delivery: delivery)

        if delivery == .hidTap, let restorePoint {
            CGWarpMouseCursorPosition(restorePoint)
        }
        pause(40)
    }

    /// 合成 command 键的按下/抬起。键盘事件里 keycode 55 就是左 Command，
    /// 系统会把它当修饰键处理，从而更新全局修饰键状态。
    private static func postCommandKey(
        source: CGEventSource?, down: Bool, ownerPID: pid_t, delivery: Delivery
    ) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: 55, keyDown: down) else { return }
        event.flags = down ? .maskCommand : []
        switch delivery {
        case .toProcess: event.postToPid(ownerPID)
        case .hidTap: event.post(tap: .cghidEventTap)
        }
        pause(15)
    }

    private static func pause(_ milliseconds: UInt32) {
        usleep(milliseconds * 1000)
    }

    /// 当前指针位置（Quartz 全局坐标）。NSEvent 给的是 AppKit 左下原点，这里转过来。
    private static func currentCursorQuartzPoint() -> CGPoint? {
        guard let primaryTop = NSScreen.screens.first?.frame.maxY else { return nil }
        let appKit = NSEvent.mouseLocation
        return CGPoint(x: appKit.x, y: primaryTop - appKit.y)
    }
}
