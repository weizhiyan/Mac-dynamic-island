import SwiftUI
import AppKit

struct AppIconView: View {
    let item: AppItem
    let size: CGFloat
    var reveal: Bool
    var magnification: CGFloat = 1

    var body: some View {
        Image(nsImage: IconLoader.icon(for: item))
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.30, style: .continuous))
            .scaleEffect(magnification, anchor: .center)
            .shadow(color: .black.opacity(0.30), radius: 8, y: 4)
            .opacity(reveal ? 1 : 0)
            .offset(y: reveal ? 0 : 12)
            .animation(.islandReveal, value: reveal)
            .animation(.spring(response: 0.18, dampingFraction: 0.82), value: magnification)
            .onTapGesture {
                ClickProbe.log("onTapGesture \(item.name)")
                AppLauncher.launch(item)
            }
            .background(
                TooltipHostingView(title: item.name)
                    .frame(width: size, height: size)
            )
    }
}

// MARK: - NSPopover 悬停气泡提示

/// 包装 NSView 以承载 NSTrackingArea 和 NSPopover，鼠标移到图标上即弹出应用名称气泡
private struct TooltipHostingView: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> TooltipNSView {
        let view = TooltipNSView(title: title)
        return view
    }

    func updateNSView(_ nsView: TooltipNSView, context: Context) {
        nsView.updateTitle(title)
    }
}

/// 原生 NSView：管理 NSTrackingArea 与 NSPopover 的生命周期
final class TooltipNSView: NSView {
    private var title: String
    private var trackingArea: NSTrackingArea?
    private var popover: NSPopover?
    /// 全局唯一的当前气泡
    private static weak var activeTip: TooltipNSView?

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        popover?.close()
    }

    func updateTitle(_ newTitle: String) {
        title = newTitle
    }

    // MARK: - TrackingArea

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea { removeTrackingArea(old) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
    }

    // MARK: - Mouse Events

    override func hitTest(_ point: NSPoint) -> NSView? {
        let result = super.hitTest(point)
        if result != nil {
            ClickProbe.log("hitTest 命中 \(title) → \(type(of: result!))")
        }
        return result
    }

    override func mouseDown(with event: NSEvent) {
        ClickProbe.log("TooltipNSView.mouseDown \(title)")
        super.mouseDown(with: event)
    }

    override func mouseEntered(with event: NSEvent) {
        ClickProbe.log("悬停进入 \(title)")
        showPopover()
    }

    override func mouseExited(with event: NSEvent) {
        ClickProbe.log("悬停离开 \(title)")
        hidePopover()
    }

    // MARK: - NSPopover

    private func showPopover() {
        guard !ClickProbe.tipDisabled else { return }
        // 已显示则不重复创建
        guard popover == nil else { return }
        // 同一时刻只留一个气泡：光标被瞬移（或岛体收起）时 mouseExited 不一定触发，
        // 旧气泡会一直挂在屏幕上盖住别的图标。
        if let other = Self.activeTip, other !== self { other.hidePopover() }
        let pop = NSPopover()
        // 用 .applicationDefined 而不是 .transient：transient 会让 AppKit 自己装一个
        // 关闭监听器，把"用来关气泡"的那一次点击吃掉。气泡的显示/隐藏本来就由
        // mouseEntered/mouseExited 全权管理，不需要 AppKit 插手。
        pop.behavior = ClickProbe.legacyTip ? .transient : .applicationDefined
        pop.animates = true             // 使用原生弹出动画
        pop.contentSize = NSSize(width: preferredPopoverWidth(), height: 32)
        pop.contentViewController = NSHostingController(
            rootView: TooltipContentView(title: title)
        )
        pop.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
        // 气泡纯展示，必须让点击穿过去。第一排图标的气泡会被 AppKit 翻到下方、
        // 正好压住第二排图标（反之亦然），不加这一行时落在重叠区的那一下点击
        // 会被气泡窗口接走，用户看到的就是"点了没反应，应用打不开"。
        if !ClickProbe.legacyTip {
            pop.contentViewController?.view.window?.ignoresMouseEvents = true
        }
        popover = pop
        Self.activeTip = self
        ClickProbe.log("气泡显示 \(title) 图标窗口坐标=\(window?.convertToScreen(convert(bounds, to: nil)) ?? .zero) 气泡=\(pop.contentViewController?.view.window?.frame ?? .zero)")
    }

    private func hidePopover() {
        popover?.close()
        popover = nil
        if Self.activeTip === self { Self.activeTip = nil }
    }

    /// 岛体收起时清掉残留气泡：收起时窗口直接 orderOut，mouseExited 不会触发。
    static func dismissActiveTip() {
        activeTip?.hidePopover()
    }

    /// 根据标题长度动态估算气泡宽度（最小 80，最大 320）
    private func preferredPopoverWidth() -> CGFloat {
        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let textWidth = (title as NSString).size(withAttributes: attrs).width
        return min(max(textWidth + 28, 80), 320)
    }
}

/// 气泡内的 SwiftUI 内容视图：应用名称标签
private struct TooltipContentView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.primary)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(minWidth: 80, maxWidth: 320)
            .fixedSize()
    }
}
