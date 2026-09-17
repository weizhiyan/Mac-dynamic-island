import AppKit

struct NotchArea {
    let frame: CGRect
    let anchor: CGPoint
    let screenWidth: CGFloat
    let screenFrame: CGRect
    let topInset: CGFloat
}

enum NotchDetector {
    static func current() -> NotchArea {
        let screens = NSScreen.screens
        if let pointerScreen = screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) {
            return current(on: pointerScreen)
        }
        guard let screen = mainScreen() else {
            let fallback = CGRect(x: 0, y: 0, width: 1440, height: 900)
            return NotchArea(
                frame: CGRect(x: 0, y: fallback.maxY, width: 220, height: 0),
                anchor: CGPoint(x: fallback.midX, y: fallback.maxY),
                screenWidth: fallback.width,
                screenFrame: fallback,
                topInset: 0
            )
        }
        return current(on: screen)
    }

    static func current(on screen: NSScreen) -> NotchArea {
        let frame = screen.frame
        let width: CGFloat = 220
        let topInset = max(screen.safeAreaInsets.top, 0)
        let y = frame.maxY - topInset
        let x = frame.midX - width / 2
        return NotchArea(
            frame: CGRect(x: x, y: y, width: width, height: topInset),
            anchor: CGPoint(x: frame.midX, y: y),
            screenWidth: frame.width,
            screenFrame: frame,
            topInset: topInset
        )
    }

    /// 灵动岛所在屏幕：优先使用鼠标所在屏幕；鼠标不在屏幕范围内时，
    /// 再回退到内建屏 / 有刘海屏 / 系统第一块屏幕。
    ///
    /// 不使用 `NSScreen.main`，因为它表示键盘焦点窗口所在屏幕，
    /// 不一定是用户当前操作的屏幕。
    static func mainScreen() -> NSScreen? {
        let screens = NSScreen.screens
        if let notched = screens.first(where: { $0.safeAreaInsets.top > 0 }) { return notched }
        if let builtin = screens.first(where: { $0.isBuiltin }) { return builtin }
        return screens.first
    }
}

extension NSScreen {
    /// 是否是内建屏（笔记本屏幕）
    var isBuiltin: Bool {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        else { return false }
        return CGDisplayIsBuiltin(number) != 0
    }
}
