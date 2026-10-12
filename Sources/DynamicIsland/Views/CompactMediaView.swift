import AppKit

/// 收起态刘海内的透明内容层：左侧固定的音乐头像槽位 + 右侧固定槽位的白色波纹。
/// 黑色主体仍由灵动岛窗口层绘制，本层只画内容、不接收鼠标事件。
final class CompactMediaView: NSView {
    private static let horizontalInset: CGFloat = 8
    private static let artworkGap: CGFloat = 10
    private static let artworkSide: CGFloat = 20
    private static let waveformSlotSide: CGFloat = 20

    /// 收起态内容整体占用宽度：两侧内边距 + 头像 + 间距 + 波纹槽，紧凑带不会窄于它。
    static let contentWidth: CGFloat = horizontalInset * 2 + artworkSide + artworkGap + waveformSlotSide

    private let artworkLayer = CALayer()
    private let waveform = WaveformLayer()
    private var symbolFallback: NSImage?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true

        artworkLayer.cornerRadius = 0
        artworkLayer.masksToBounds = true
        artworkLayer.contentsGravity = .resizeAspectFill
        artworkLayer.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        layer?.addSublayer(artworkLayer)
        layer?.addSublayer(waveform)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var waveformMode: WaveformLayer.Mode { waveform.mode }
    var waveformBarCount: Int { waveform.barCount }

    /// 真实音频电平直通波纹，不经过布局。
    func setWaveformLevels(_ levels: [CGFloat]) {
        waveform.setLevels(levels)
    }

    /// 内容槽位只随刘海几何变化，播放状态刷新不会改动布局。
    override var frame: NSRect {
        get { super.frame }
        set {
            super.frame = newValue
            layoutContent()
        }
    }

    override func layout() {
        super.layout()
        layoutContent()
    }

    private func layoutContent() {
        let height = bounds.height
        guard height > 0 else { return }
        let side = min(Self.artworkSide, height)
        let slotSide = min(Self.waveformSlotSide, height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        artworkLayer.frame = CGRect(
            x: bounds.minX + Self.horizontalInset,
            y: bounds.midY - side / 2,
            width: side,
            height: side
        )
        artworkLayer.cornerRadius = side / 2
        let slotStart = artworkLayer.frame.maxX + Self.artworkGap
        let slotRight = bounds.maxX - Self.horizontalInset
        let slotX = max(slotRight - slotSide, slotStart)
        waveform.frame = CGRect(
            x: slotX,
            y: bounds.midY - slotSide / 2,
            width: max(slotRight - slotX, 0),
            height: slotSide
        )
        CATransaction.commit()
        waveform.relayout()
    }

    func update(image: NSImage?, mode: WaveformLayer.Mode, tint: NSColor?, animates: Bool) {
        let scale = window?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        artworkLayer.contentsScale = scale
        artworkLayer.contents = image ?? whiteSymbolImage()
        waveform.contentsScale = scale
        CATransaction.commit()
        waveform.setTint(tint)
        waveform.apply(mode: mode, animate: animates)
    }

    /// 播放器既没有封面也没有图标时的最终回退。
    private func whiteSymbolImage() -> NSImage? {
        if let cached = symbolFallback { return cached }
        guard let symbol = NSImage(systemSymbolName: "music.note", accessibilityDescription: "音乐") else { return nil }
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.white.set()
            rect.fill()
            symbol.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1)
            return true
        }
        symbolFallback = image
        return image
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
