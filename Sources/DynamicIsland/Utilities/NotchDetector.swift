import AppKit

struct NotchArea {
    let frame: CGRect
    let anchor: CGPoint
    let screenWidth: CGFloat
    let screenFrame: CGRect
    let topInset: CGFloat
}

/// 收起态紧凑内容带的几何结果，坐标为 AppKit point（不是物理像素）。
struct CompactBand {
    let frame: CGRect
    /// 顶部两侧过渡圆角。
    let topRadius: CGFloat
    /// 底部两个凸圆角，决定「像不像刘海」。
    let bottomRadius: CGFloat
    /// 刘海本身的 frame，用于把内容收进物理缺口以内。
    let notchFrame: CGRect
}

enum NotchDetector {
    /// 收起态在刘海左右两侧各争取的内容宽度。内容已能完整收进刘海内，默认不再横向外扩。
    static let compactSideExtension: CGFloat = 0
    /// 原生刘海的底部凸圆角约为高度的 0.28。顶部贴着屏幕边缘，不能切出内收圆角。
    static let notchBottomRadiusRatio: CGFloat = 0.28

    /// 由刘海几何推导收起态紧凑内容带：宽度取「刘海宽度 / 调用方加宽 / 内容宽度」的最大值，
    /// 纵向严格等于刘海高度，顶边贴在屏幕顶端，不向屏幕外溢出。
    /// 没有刘海时返回 nil（不渲染紧凑内容）。
    static func compactBand(
        notch: NotchArea,
        baseWidth: CGFloat,
        limitWidth: CGFloat,
        sideExtension: CGFloat = compactSideExtension,
        contentWidth: CGFloat = 0,
        widthOverride: CGFloat? = nil,
        heightOverride: CGFloat? = nil,
        topRadiusOverride: CGFloat? = nil,
        bottomRadiusOverride: CGFloat? = nil,
        verticalOffset: CGFloat = 0
    ) -> CompactBand? {
        guard notch.topInset > 0, notch.frame.width > 0, notch.frame.height > 0 else { return nil }
        let minWidth: CGFloat = 24
        guard limitWidth >= minWidth else { return nil }
        let height = min(max(heightOverride ?? notch.frame.height, 1), notch.screenFrame.height)
        let autoWidth = max(baseWidth, notch.frame.width + sideExtension * 2, contentWidth)
        let width = min(max(widthOverride ?? autoWidth, minWidth), limitWidth)
        let maxX = max(notch.screenFrame.minX, notch.screenFrame.maxX - width)
        let x = min(max(notch.anchor.x - width / 2, notch.screenFrame.minX), maxX)
        return CompactBand(
            frame: CGRect(x: x, y: notch.frame.maxY - height + verticalOffset, width: width, height: height),
            topRadius: min(max(topRadiusOverride ?? 0, 0), min(width / 2, height)),
            bottomRadius: min(max(bottomRadiusOverride ?? height * notchBottomRadiusRatio, 0), min(width / 2, height)),
            notchFrame: notch.frame
        )
    }

    static func current() -> NotchArea {
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
        let safeTopInset = max(screen.safeAreaInsets.top, 0)
        let inferred = inferredNotch(on: screen)
        let width = inferred?.width ?? 220
        let topInset = inferred?.height ?? safeTopInset
        let y = frame.maxY - topInset
        let x = inferred?.minX ?? (frame.midX - width / 2)
        return NotchArea(
            frame: CGRect(x: x, y: y, width: width, height: topInset),
            anchor: CGPoint(x: x + width / 2, y: y),
            screenWidth: frame.width,
            screenFrame: frame,
            topInset: topInset
        )
    }

    private static func inferredNotch(on screen: NSScreen) -> (minX: CGFloat, width: CGFloat, height: CGFloat)? {
        guard let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea,
              left.maxX > screen.frame.minX,
              right.minX < screen.frame.maxX,
              right.minX > left.maxX else { return nil }

        let gapWidth = right.minX - left.maxX
        let gapHeight = min(left.height, right.height)
        guard gapWidth >= 100, gapHeight > 0 else { return nil }
        return (left.maxX, gapWidth, gapHeight)
    }

    /// 灵动岛固定在系统主屏幕。
    ///
    /// `NSScreen.screens` 的第一个屏幕是系统主屏幕。不能根据鼠标位置
    /// 动态切换，否则鼠标移到副屏时悬停探测器和岛屿窗口都会跟着跳屏。
    static func mainScreen() -> NSScreen? {
        let screens = NSScreen.screens
        return screens.first
    }
}
