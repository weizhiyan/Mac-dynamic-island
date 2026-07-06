import Foundation
import Combine
import QuartzCore

enum IslandMode: String, CaseIterable {
    case systemNotch
}

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    private let defaults = UserDefaults.standard

    // MARK: - 应用网格
    /// 应用图标尺寸（像素）
    @Published var iconSize: CGFloat {
        didSet { defaults.set(iconSize, forKey: Key.iconSize) }
    }
    /// 应用网格列数
    @Published var columns: Int {
        didSet { defaults.set(columns, forKey: Key.columns) }
    }
    /// 应用图标间距（像素）
    @Published var iconSpacing: CGFloat {
        didSet { defaults.set(iconSpacing, forKey: Key.iconSpacing) }
    }

    // MARK: - 悬停触发
    /// 鼠标悬停触发区域宽度（像素）
    @Published var hoverZoneWidth: CGFloat {
        didSet { defaults.set(hoverZoneWidth, forKey: Key.hoverZoneWidth) }
    }
    /// 鼠标悬停触发区域高度（像素）
    @Published var hoverZoneHeight: CGFloat {
        didSet { defaults.set(hoverZoneHeight, forKey: Key.hoverZoneHeight) }
    }
    /// 触发区域纵向偏移（像素）— 正值向上移，0=紧贴刘海底部下方
    @Published var hoverZoneYOffset: CGFloat {
        didSet { defaults.set(hoverZoneYOffset, forKey: Key.hoverZoneYOffset) }
    }
    /// 进入触发区域的防抖延迟（秒）
    @Published var hoverEnterDelay: TimeInterval {
        didSet { defaults.set(hoverEnterDelay, forKey: Key.hoverEnterDelay) }
    }
    /// 离开后的隐藏延迟（秒）
    @Published var hideDelay: TimeInterval {
        didSet { defaults.set(hideDelay, forKey: Key.hideDelay) }
    }

    // MARK: - 布局
    /// 整体向上偏移量（像素）— topBar + mainBody 一起往刘海方向移
    @Published var topBarYOffset: CGFloat {
        didSet { defaults.set(topBarYOffset, forKey: Key.topBarYOffset) }
    }
    /// 内容边距（像素）— 图标网格与岛屿左右/底部边缘的间距
    @Published var contentPadding: CGFloat {
        didSet {
            if bottomPadding != contentPadding {
                bottomPadding = contentPadding
            }
            defaults.set(contentPadding, forKey: Key.contentPadding)
        }
    }
    /// 内容上间距（像素）— 图标网格与刘海/岛屿顶部的距离
    @Published var contentTopPadding: CGFloat {
        didSet { defaults.set(contentTopPadding, forKey: Key.contentTopPadding) }
    }
    /// 底部间距（像素）— 图标网格与岛屿底部的间距
    @Published var bottomPadding: CGFloat {
        didSet { defaults.set(bottomPadding, forKey: Key.bottomPadding) }
    }
    /// 收缩态细线宽度（像素）
    @Published var compactWidth: CGFloat {
        didSet { defaults.set(compactWidth, forKey: Key.compactWidth) }
    }
    /// 收缩态细线高度（像素）
    @Published var compactHeight: CGFloat {
        didSet { defaults.set(compactHeight, forKey: Key.compactHeight) }
    }
    /// 顶部融合矩形高度（像素）— 需满足 height/(height+2*blur) > 0.47 才不会被滤镜吃掉
    @Published var topBarHeight: CGFloat {
        didSet {
            // 约束：topBarHeight >= max(27, blur * 1.77)
            let minHeight = max(27.0, ceil(gooeyBlurRadius * 1.77))
            if topBarHeight < minHeight {
                topBarHeight = minHeight
            }
            defaults.set(topBarHeight, forKey: Key.topBarHeight)
        }
    }
    /// gooey 滤镜高斯模糊半径（像素）
    @Published var gooeyBlurRadius: Double {
        didSet {
            // 联动：blur 增大时自动抬高 topBarHeight 以满足融合约束
            let minHeight = max(27.0, ceil(gooeyBlurRadius * 1.77))
            if topBarHeight < minHeight {
                topBarHeight = minHeight  // 触发 topBarHeight.didSet
            }
            defaults.set(gooeyBlurRadius, forKey: Key.gooeyBlurRadius)
        }
    }

    /// topBarWidth 始终为 expandedWidth 的 1.5 倍（硬约束，不可单独设置）
    var topBarWidth: CGFloat { expandedWidth * 1.5 }

    /// 展开态岛屿宽度 — 根据图标列数、尺寸、间距、内边距自动计算
    var expandedWidth: CGFloat {
        let cols = max(1, columns)
        return CGFloat(cols) * iconSize + CGFloat(cols - 1) * iconSpacing + contentPadding * 2
    }
    /// 展开态岛屿高度 — 根据图标行数、尺寸、间距、内边距自动计算
    var expandedHeight: CGFloat {
        let cols = max(1, columns)
        let rows = max(1, Int(ceil(Double(AppStore.shared.apps.count) / Double(cols))))
        return CGFloat(rows) * iconSize + CGFloat(rows - 1) * iconSpacing + contentTopPadding + contentPadding
    }

    // MARK: - 动画
    /// 展开动画总时长（秒）
    @Published var expandDuration: TimeInterval {
        didSet { defaults.set(expandDuration, forKey: Key.expandDuration) }
    }
    /// 收起动画时长（秒）
    @Published var collapseDuration: TimeInterval {
        didSet { defaults.set(collapseDuration, forKey: Key.collapseDuration) }
    }
    /// 内容（应用图标）淡入延迟（秒）
    @Published var revealDelay: TimeInterval {
        didSet { defaults.set(revealDelay, forKey: Key.revealDelay) }
    }
    /// 鼓起阶段时长占展开总时长的比例（0.1–0.5）
    @Published var bulgeDurationRatio: Double {
        didSet { defaults.set(bulgeDurationRatio, forKey: Key.bulgeDurationRatio) }
    }
    /// 鼓起矩形宽度（像素）
    @Published var bulgeWidth: CGFloat {
        didSet { defaults.set(bulgeWidth, forKey: Key.bulgeWidth) }
    }
    /// 鼓起矩形高度（像素）
    @Published var bulgeHeight: CGFloat {
        didSet { defaults.set(bulgeHeight, forKey: Key.bulgeHeight) }
    }
    /// 内容淡入时长（秒）
    @Published var contentFadeInDuration: TimeInterval {
        didSet { defaults.set(contentFadeInDuration, forKey: Key.contentFadeInDuration) }
    }
    /// 内容淡出时长（秒）
    @Published var contentFadeOutDuration: TimeInterval {
        didSet { defaults.set(contentFadeOutDuration, forKey: Key.contentFadeOutDuration) }
    }
    // MARK: - 时间曲线（贝塞尔控制点，格式 "x1, y1, x2, y2"）
    /// 展开动画贝塞尔控制点，如 "0.65, 0, 0.35, 1"
    @Published var expandTimingCurve: String {
        didSet { defaults.set(expandTimingCurve, forKey: Key.expandTimingCurve) }
    }
    /// 收起动画贝塞尔控制点，如 "0.25, 0.1, 0.25, 1"
    @Published var collapseTimingCurve: String {
        didSet { defaults.set(collapseTimingCurve, forKey: Key.collapseTimingCurve) }
    }
    /// 展开动画 CAMediaTimingFunction（从字符串解析 4 个控制点）
    var expandTimingFunction: CAMediaTimingFunction {
        timingFunction(from: expandTimingCurve, fallback: (0.65, 0, 0.35, 1))
    }
    /// 收起动画 CAMediaTimingFunction（从字符串解析 4 个控制点）
    var collapseTimingFunction: CAMediaTimingFunction {
        timingFunction(from: collapseTimingCurve, fallback: (0.25, 0.1, 0.25, 1))
    }
    /// 解析 "x1, y1, x2, y2" 格式字符串为 4 个 Float，失败则用 fallback
    private func timingFunction(from str: String, fallback: (Float, Float, Float, Float)) -> CAMediaTimingFunction {
        let parts = str.split(separator: ",").compactMap { Float($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 4 {
            return CAMediaTimingFunction(controlPoints: parts[0], parts[1], parts[2], parts[3])
        }
        return CAMediaTimingFunction(controlPoints: fallback.0, fallback.1, fallback.2, fallback.3)
    }

    // MARK: - 圆角
    /// 收缩态圆角半径（像素）
    @Published var compactCornerRadius: CGFloat {
        didSet { defaults.set(compactCornerRadius, forKey: Key.compactCornerRadius) }
    }
    /// 展开态圆角半径（像素）
    @Published var expandedCornerRadius: CGFloat {
        didSet { defaults.set(expandedCornerRadius, forKey: Key.expandedCornerRadius) }
    }
    /// 鼓起态圆角半径（像素）
    @Published var bulgeCornerRadius: CGFloat {
        didSet { defaults.set(bulgeCornerRadius, forKey: Key.bulgeCornerRadius) }
    }

    // MARK: - 模式
    @Published var mode: IslandMode {
        didSet { defaults.set(mode.rawValue, forKey: Key.mode) }
    }

    // MARK: - 系统
    @Published var launchAtLoginEnabled: Bool {
        didSet {
            let actualValue = LoginItemManager.setEnabled(launchAtLoginEnabled)
            defaults.set(actualValue, forKey: Key.launchAtLoginEnabled)
            if actualValue != launchAtLoginEnabled {
                launchAtLoginEnabled = actualValue
            }
        }
    }

    // MARK: - Key 定义
    private enum Key {
        // 应用网格
        static let iconSize = "iconSize"
        static let columns = "columns"
        static let iconSpacing = "iconSpacing"
        // 悬停触发
        static let hoverZoneWidth = "hoverZoneWidth"
        static let hoverZoneHeight = "hoverZoneHeight"
        static let hoverZoneYOffset = "hoverZoneYOffset"
        static let hoverEnterDelay = "hoverEnterDelay"
        static let hideDelay = "hideDelay"
        // 布局
        static let topBarYOffset = "topBarYOffset"
        static let contentPadding = "contentPadding"
        static let contentTopPadding = "contentTopPadding"
        static let bottomPadding = "bottomPadding"
        static let compactWidth = "compactWidth"
        static let compactHeight = "compactHeight"
        static let topBarHeight = "topBarHeight"
        static let gooeyBlurRadius = "gooeyBlurRadius"
        // 动画
        static let expandDuration = "expandDuration"
        static let collapseDuration = "collapseDuration"
        static let revealDelay = "revealDelay"
        static let bulgeDurationRatio = "bulgeDurationRatio"
        static let bulgeWidth = "bulgeWidth"
        static let bulgeHeight = "bulgeHeight"
        static let contentFadeInDuration = "contentFadeInDuration"
        static let contentFadeOutDuration = "contentFadeOutDuration"
        // 时间曲线
        static let expandTimingCurve = "expandTimingCurve"
        static let collapseTimingCurve = "collapseTimingCurve"
        // 圆角
        static let compactCornerRadius = "compactCornerRadius"
        static let expandedCornerRadius = "expandedCornerRadius"
        static let bulgeCornerRadius = "bulgeCornerRadius"
        // 模式
        static let mode = "islandMode"
        // 系统
        static let launchAtLoginEnabled = "launchAtLoginEnabled"
        // 版本号 — 每次修改默认值时 +1，旧缓存会自动清空
        static let settingsVersion = "settingsVersion"
    }

    /// 当前设置版本号。**修改任何默认值时务必 +1**，
    /// 这样老用户机器上的旧缓存会被自动清掉，新默认值才会生效。
    private static let currentVersion = 11

    private init() {
        let d = UserDefaults.standard

        // 版本号不匹配（首次安装或升级后）→ 清空所有旧设置，避免旧默认值覆盖新默认值
        if d.integer(forKey: Key.settingsVersion) != Self.currentVersion {
            for key in [Key.iconSize, Key.columns, Key.iconSpacing,
                        Key.hoverZoneWidth, Key.hoverZoneHeight, Key.hoverZoneYOffset, Key.hoverEnterDelay, Key.hideDelay,
                        Key.topBarYOffset, Key.contentPadding, Key.contentTopPadding, Key.bottomPadding,
                        Key.compactWidth, Key.compactHeight, Key.topBarHeight, Key.gooeyBlurRadius,
                        Key.expandDuration, Key.collapseDuration, Key.revealDelay,
                        Key.bulgeDurationRatio, Key.bulgeWidth, Key.bulgeHeight,
                        Key.contentFadeInDuration, Key.contentFadeOutDuration,
                        Key.expandTimingCurve, Key.collapseTimingCurve,
                        Key.compactCornerRadius, Key.expandedCornerRadius, Key.bulgeCornerRadius,
                        Key.mode, Key.launchAtLoginEnabled] {
                d.removeObject(forKey: key)
            }
            d.set(Self.currentVersion, forKey: Key.settingsVersion)
        }

        // 读取（此时若没有用户自定义值，就用代码里的最新默认值）
        // 应用网格
        iconSize = d.object(forKey: Key.iconSize) as? CGFloat ?? 60
        columns = d.object(forKey: Key.columns) as? Int ?? 6
        iconSpacing = d.object(forKey: Key.iconSpacing) as? CGFloat ?? 13
        // 悬停触发
        hoverZoneWidth = d.object(forKey: Key.hoverZoneWidth) as? CGFloat ?? 217
        hoverZoneHeight = d.object(forKey: Key.hoverZoneHeight) as? CGFloat ?? 7
        hoverZoneYOffset = d.object(forKey: Key.hoverZoneYOffset) as? CGFloat ?? 39
        hoverEnterDelay = d.object(forKey: Key.hoverEnterDelay) as? TimeInterval ?? 0
        hideDelay = d.object(forKey: Key.hideDelay) as? TimeInterval ?? 0.12
        // 布局
        topBarYOffset = d.object(forKey: Key.topBarYOffset) as? CGFloat ?? 38
        contentPadding = d.object(forKey: Key.contentPadding) as? CGFloat ?? 16
        contentTopPadding = d.object(forKey: Key.contentTopPadding) as? CGFloat ?? 36
        bottomPadding = d.object(forKey: Key.bottomPadding) as? CGFloat ?? 16
        compactWidth = d.object(forKey: Key.compactWidth) as? CGFloat ?? 140
        compactHeight = d.object(forKey: Key.compactHeight) as? CGFloat ?? 1
        topBarHeight = d.object(forKey: Key.topBarHeight) as? CGFloat ?? 40
        gooeyBlurRadius = d.object(forKey: Key.gooeyBlurRadius) as? Double ?? 16
        // 动画
        expandDuration = d.object(forKey: Key.expandDuration) as? TimeInterval ?? 0.5
        collapseDuration = d.object(forKey: Key.collapseDuration) as? TimeInterval ?? 0.7
        revealDelay = d.object(forKey: Key.revealDelay) as? TimeInterval ?? 0.31
        bulgeDurationRatio = d.object(forKey: Key.bulgeDurationRatio) as? Double ?? 0.22
        bulgeWidth = d.object(forKey: Key.bulgeWidth) as? CGFloat ?? 76
        bulgeHeight = d.object(forKey: Key.bulgeHeight) as? CGFloat ?? 46
        contentFadeInDuration = d.object(forKey: Key.contentFadeInDuration) as? TimeInterval ?? 0.35
        contentFadeOutDuration = d.object(forKey: Key.contentFadeOutDuration) as? TimeInterval ?? 0.08
        // 时间曲线 — 展开: 0.65, 0, 0.35, 1  收起: 0.25, 0.1, 0.25, 1 (=easeInOut)
        expandTimingCurve = d.string(forKey: Key.expandTimingCurve) ?? "0.65, 0, 0.35, 1"
        collapseTimingCurve = d.string(forKey: Key.collapseTimingCurve) ?? "0.25, 0.1, 0.25, 1"
        // 圆角
        compactCornerRadius = d.object(forKey: Key.compactCornerRadius) as? CGFloat ?? 2
        expandedCornerRadius = d.object(forKey: Key.expandedCornerRadius) as? CGFloat ?? 16
        bulgeCornerRadius = d.object(forKey: Key.bulgeCornerRadius) as? CGFloat ?? 23
        // 模式
        mode = IslandMode(rawValue: d.string(forKey: Key.mode) ?? "") ?? .systemNotch
        // 系统
        launchAtLoginEnabled = LoginItemManager.isEnabled
    }

    /// 恢复所有参数到默认值（用于设置面板的「恢复默认」按钮）
    func restoreDefaults() {
        // 注意顺序：先设 gooeyBlurRadius 再设 topBarHeight，避免 clamp 联动抬高
        iconSize = 60
        columns = 6
        iconSpacing = 13
        hoverZoneWidth = 217
        hoverZoneHeight = 7
        hoverZoneYOffset = 39
        hoverEnterDelay = 0
        hideDelay = 0.12
        topBarYOffset = 38
        contentPadding = 16
        contentTopPadding = 36
        bottomPadding = 16
        compactWidth = 140
        compactHeight = 1
        gooeyBlurRadius = 16
        topBarHeight = 40
        expandDuration = 0.5
        collapseDuration = 0.7
        revealDelay = 0.31
        bulgeDurationRatio = 0.22
        bulgeWidth = 76
        bulgeHeight = 46
        contentFadeInDuration = 0.35
        contentFadeOutDuration = 0.08
        expandTimingCurve = "0.65, 0, 0.35, 1"
        collapseTimingCurve = "0.25, 0.1, 0.25, 1"
        compactCornerRadius = 2
        expandedCornerRadius = 16
        bulgeCornerRadius = 23
        mode = .systemNotch
        launchAtLoginEnabled = false
    }
}
