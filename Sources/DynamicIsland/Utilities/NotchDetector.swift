import AppKit

struct NotchArea {
    let frame: CGRect
    let anchor: CGPoint
    let screenWidth: CGFloat
}

enum NotchDetector {
    static func current() -> NotchArea {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return NotchArea(frame: CGRect(x: 0, y: 0, width: 220, height: 24), anchor: CGPoint(x: 110, y: 0), screenWidth: 1440)
        }
        let frame = screen.frame
        let width: CGFloat = 220
        let height: CGFloat = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 24
        let x = frame.midX - width / 2
        let y = frame.maxY - height
        return NotchArea(frame: CGRect(x: x, y: y, width: width, height: height), anchor: CGPoint(x: frame.midX, y: y), screenWidth: frame.width)
    }
}
