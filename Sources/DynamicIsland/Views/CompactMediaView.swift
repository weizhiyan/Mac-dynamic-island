import AppKit

/// 收起态刘海带的透明内容层：左侧固定的音乐头像槽位 + 右侧固定槽位的白色波纹。
/// 黑色主体仍由灵动岛窗口层绘制，本层只画内容、不接收鼠标事件。
final class CompactMediaView: NSView {
    /// 收起态播放视觉暂时关闭；保留实现，后续打磨完成后可重新启用。
    static let isPlaybackEffectEnabled = false

    private static let horizontalInset: CGFloat = 8
    private static let artworkGap: CGFloat = 10
    private static let artworkSide: CGFloat = 20
    private static let waveformSlotSide: CGFloat = 20
    private static let progressRingSide: CGFloat = 26

    /// 左右各留出 34pt，让头像与波纹落在物理刘海之外、菜单栏可见区域内。
    static let sideExtension = NotchDetector.compactSideExtension

    /// 收起态内容整体占用宽度：两侧内边距 + 头像 + 间距 + 波纹槽，紧凑带不会窄于它。
    static let contentWidth: CGFloat = horizontalInset * 2 + artworkSide + artworkGap + waveformSlotSide

    private let artworkLayer = CALayer()
    private let progressTrackLayer = CAShapeLayer()
    private let progressLayer = CAShapeLayer()
    private let waveform = WaveformLayer()
    private var symbolFallback: NSImage?
    private var displayedImage: NSImage?
    private var displayedProgress: CGFloat = 0

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
        for ring in [progressTrackLayer, progressLayer] {
            ring.fillColor = NSColor.clear.cgColor
            ring.lineWidth = 1.4
            ring.lineCap = .round
            ring.isHidden = true
            layer?.addSublayer(ring)
        }
        progressTrackLayer.strokeColor = NSColor.white.withAlphaComponent(0.14).cgColor
        progressLayer.strokeColor = NSColor.white.withAlphaComponent(0.82).cgColor
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
        let ringSide = min(Self.progressRingSide, height)
        let ringRect = CGRect(
            x: artworkLayer.frame.midX - ringSide / 2,
            y: bounds.midY - ringSide / 2,
            width: ringSide,
            height: ringSide
        )
        for ring in [progressTrackLayer, progressLayer] {
            ring.frame = bounds
            ring.path = CGPath(ellipseIn: ringRect, transform: nil)
        }
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

    func update(
        image: NSImage?,
        mode: WaveformLayer.Mode,
        tint: NSColor?,
        progress: CGFloat?,
        animates: Bool,
        progressAnimates: Bool
    ) {
        let scale = window?.backingScaleFactor ?? 2
        let imageChanged = displayedImage !== image
        displayedImage = image
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        artworkLayer.contentsScale = scale
        artworkLayer.contents = image ?? whiteSymbolImage()
        let ringColor = tint ?? NSColor.white
        artworkLayer.borderWidth = 0.5
        artworkLayer.borderColor = ringColor.withAlphaComponent(0.26).cgColor
        progressTrackLayer.strokeColor = ringColor.withAlphaComponent(0.16).cgColor
        progressLayer.strokeColor = ringColor.withAlphaComponent(0.82).cgColor
        waveform.contentsScale = scale
        CATransaction.commit()
        if imageChanged, animates {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.22
            transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
            artworkLayer.add(transition, forKey: "artwork.fade")
        }
        updateProgress(progress, mode: mode, animates: progressAnimates)
        waveform.setTint(tint)
        waveform.apply(mode: mode, animate: animates)
    }

    private func updateProgress(_ progress: CGFloat?, mode: WaveformLayer.Mode, animates: Bool) {
        let visible = mode != .hidden && progress != nil
        progressTrackLayer.isHidden = !visible
        progressLayer.isHidden = !visible
        guard let progress else {
            displayedProgress = 0
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            progressLayer.strokeEnd = 0
            CATransaction.commit()
            return
        }

        let next = min(max(progress, 0), 1)
        let current = progressLayer.presentation()?.strokeEnd ?? progressLayer.strokeEnd
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progressLayer.strokeEnd = next
        CATransaction.commit()

        guard animates, next >= displayedProgress, abs(next - current) > 0.001 else {
            displayedProgress = next
            return
        }
        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = current
        animation.toValue = next
        animation.duration = 2
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        progressLayer.add(animation, forKey: "progress.advance")
        displayedProgress = next
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
