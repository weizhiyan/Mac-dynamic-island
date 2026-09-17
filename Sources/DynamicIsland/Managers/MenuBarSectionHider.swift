import AppKit
import ApplicationServices

/// 菜单栏收纳分隔符（Hidden Bar / Ice / Dozer 同款机制）：
/// 自建一个 NSStatusItem 作为边界，展开成超长宽度时，
/// 它左侧的图标会被 macOS 原生挤出可见区 —— 菜单栏空间真正释放。
///
/// 谁在左边完全由用户按住 ⌘ 拖拽决定：macOS 没有公开 API 能移动别的应用的状态项。
/// 因此这里只负责两件事：把边界摆到最左（默认谁都不收纳），以及在两种长度间切换。
final class MenuBarSectionHider {

    static let shared = MenuBarSectionHider()
    private init() {}

    // MARK: - 状态

    private var dividerItem: NSStatusItem?
    /// 当前是否处于「已隐藏」状态（分隔符展开成超长）
    private(set) var isCollapsed = false
    private var rehideWorkItem: DispatchWorkItem?

    /// 展开宽度：足够大即可把左侧图标全部挤出可见区（macOS 会按可用空间截断）
    private let expandedLength: CGFloat = 10000
    /// 整理时的宽度：要让用户看得见、拖得到这条边界
    private let mutationLength: CGFloat = 16
    private let autosaveName = "DynamicIsland.HiddenSectionDivider"
    private let preferredPositionMigrationKey = "DynamicIsland.HiddenSectionDividerPositionVersion"

    // MARK: - 生命周期

    func installIfNeeded() {
        guard dividerItem == nil else { return }
        migratePreferredPositionIfNeeded()
        let item = NSStatusBar.system.statusItem(withLength: mutationLength)
        item.autosaveName = autosaveName
        dividerItem = item
        item.button?.target = self
        item.button?.action = #selector(dividerClicked)
        // 打上 AX 标识：自己名下有两个状态项（主控图标 + 这条分隔符），
        // 从 AX 里读位置时要靠它认出哪个是分隔符。
        item.button?.setAccessibilityIdentifier(Self.axIdentifier)
        // 静息态就是隐藏态：用户拖到左边的图标应当一直收着
        collapse()
    }

    /// 卸载分隔符（退出时调用），被收纳的图标恢复显示
    func uninstall() {
        rehideWorkItem?.cancel()
        if let item = dividerItem {
            item.length = mutationLength
            NSStatusBar.system.removeStatusItem(item)
        }
        dividerItem = nil
        isCollapsed = false
    }

    // MARK: - 隐藏 / 显示

    /// 展开分隔符宽度，把左侧图标挤入溢出区隐藏
    func collapse() {
        rehideWorkItem?.cancel()
        if let button = dividerItem?.button {
            // 隐藏态禁用按钮，避免这条超长区域吞掉菜单栏上的点击
            button.image = nil
            button.cell?.isEnabled = false
            button.isHighlighted = false
        }
        dividerItem?.length = expandedLength
        isCollapsed = true
    }

    /// 收起分隔符宽度，左侧图标恢复显示，并显示一个可见的边界符号供用户 ⌘ 拖拽。
    /// 可选在 delay 秒后自动重新隐藏。
    func expand(autoRehideAfter delay: TimeInterval? = nil) {
        rehideWorkItem?.cancel()
        dividerItem?.length = mutationLength
        if let button = dividerItem?.button {
            button.cell?.isEnabled = true
            button.image = Self.dividerGlyph
            button.imagePosition = .imageOnly
        }
        isCollapsed = false
        if let delay {
            let work = DispatchWorkItem { [weak self] in self?.collapse() }
            rehideWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    /// 分隔符处于可见窄条状态时不执行动作；⌘ 拖拽不应被当成点击。
    @objc private func dividerClicked() {}

    /// 分隔符当前的位置（Quartz 坐标，左上原点）。移动别人的图标时要拿它当参照：
    /// 拖到它左边就是收纳，拖到它右边就是恢复。收成超长宽度时它自己也在屏幕外，
    /// 所以调用前必须先 expand()。
    func dividerQuartzFrame() -> CGRect? {
        guard let frame = dividerItem?.button?.window?.frame,
              let primaryTop = NSScreen.screens.first?.frame.maxY,
              frame.width > 0, frame.width < 200 else { return nil }
        return CGRect(x: frame.minX, y: primaryTop - frame.maxY, width: frame.width, height: frame.height)
    }

    /// 分隔符自己的窗口 ID。新的移动方案要把它写进事件的 windowID 字段
    /// （命中测试认字段不认指针，这样才能不把真指针拖过去）。
    ///
    /// macOS 26 上 `NSWindow.windowNumber` 已经不一定塞得进 32 位（实测状态项窗口
    /// 会给出超出 `CGWindowID` 范围的值），所以这里用 `exactly:` 安全转换，
    /// 转不了就返回 nil，让调用方退回「按坐标找窗口」。
    func dividerWindowID() -> CGWindowID? {
        guard let number = dividerItem?.button?.window?.windowNumber, number > 0,
              let id = CGWindowID(exactly: number) else { return nil }
        return id
    }

    // MARK: - 从 AX 读位置（跨屏必需）

    /// 分隔符在 **AX 坐标系**里的位置。计算落点必须用它，不能用 `dividerQuartzFrame()`。
    ///
    /// 原因（实测）：macOS 26 给每块屏幕都保留一份状态项窗口副本。
    /// `button.window.frame`（AppKit）返回的可能是外接屏那一份 —— 曾经读到 x = -3805，
    /// 而图标位置是从 AX 读的、给的是内建屏那一份（x = 1278）。两个数不在同一个空间，
    /// 相减算出来的落点毫无意义（那次算出 target.x = 6，图标只被推了一格）。
    /// 图标和分隔符都从 AX 读，同一时刻取，就一定在同一个空间里。
    func dividerAXFrame() -> CGRect? {
        let items = ownStatusItems()
        if let divider = items.first(where: { $0.identifier == Self.axIdentifier }) {
            return divider.frame
        }
        // AXIdentifier 没透出来时的退路：自己名下宽度最接近整理宽度的那个
        // （主控图标是方的，比它宽），且必须真的在菜单栏那条高度上。
        return items
            .filter { $0.frame.width > 0 && abs($0.frame.width - mutationLength) <= 6 }
            .min { abs($0.frame.width - mutationLength) < abs($1.frame.width - mutationLength) }?
            .frame
    }

    /// 自己名下的状态项（主控图标 + 分隔符），带 AX 标识，供诊断和识别用。
    func ownStatusItems() -> [OwnItem] {
        guard let extras = Self.copyElement(axSelf, "AXExtrasMenuBar"),
              let children = Self.copyElements(extras, kAXChildrenAttribute as String) else { return [] }
        return children.map {
            AXUIElementSetMessagingTimeout($0, 0.3)
            return OwnItem(
                identifier: Self.copyString($0, "AXIdentifier") ?? "",
                title: Self.copyString($0, kAXTitleAttribute as String) ?? "",
                frame: Self.frame(of: $0) ?? .null
            )
        }
    }

    struct OwnItem {
        let identifier: String
        let title: String
        let frame: CGRect
    }

    private lazy var axSelf: AXUIElement = {
        let element = AXUIElementCreateApplication(getpid())
        AXUIElementSetMessagingTimeout(element, 0.3)
        return element
    }()

    private static let axIdentifier = "DynamicIsland.StashDivider"

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let value = ref, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func copyElements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success
        else { return nil }
        return ref as? [AXUIElement]
    }

    private static func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success
        else { return nil }
        return ref as? String
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var point = CGPoint.zero
        var size = CGSize.zero
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                element, kAXPositionAttribute as CFString, &positionRef) == .success,
              let positionValue = positionRef, CFGetTypeID(positionValue) == AXValueGetTypeID(),
              AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
              AXUIElementCopyAttributeValue(
                element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let sizeValue = sizeRef, CFGetTypeID(sizeValue) == AXValueGetTypeID(),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    /// 旧版本把分隔符留在第三方图标组中间。给它一个最左侧的偏好位置：
    /// 默认状态下所有图标都在它右边，也就是谁都不收纳，等用户自己拖。
    private func migratePreferredPositionIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: preferredPositionMigrationKey) < 4 else { return }
        defaults.set(10_000.0, forKey: "NSStatusItem Preferred Position \(autosaveName)")
        defaults.set(4, forKey: preferredPositionMigrationKey)
    }

    /// 整理模式下的边界符号：一条竖向虚线，视觉上和真图标区分得开。
    private static let dividerGlyph: NSImage = {
        let image = NSImage(
            systemSymbolName: "chevron.compact.left",
            accessibilityDescription: "收纳边界"
        ) ?? NSImage(size: NSSize(width: 8, height: 16))
        image.isTemplate = true
        return image
    }()
}
