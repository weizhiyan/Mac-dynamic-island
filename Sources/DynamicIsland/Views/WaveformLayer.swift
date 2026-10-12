import AppKit
import QuartzCore

/// 收起态波纹层：3 根固定槽位，只改 transform/背景色，不增删子层、不触发布局。
final class WaveformLayer: CALayer {
    enum Mode: Equatable {
        case hidden
        case playing
        case frozen
    }

    static let barSlotCount = 3
    private static let barWeights: [CGFloat] = [0.78, 1.0, 0.86]
    private static let barDurations: [Double] = [0.9, 1.15, 1.0]
    static let animationKey = "waveform.pulse"
    private static let frozenScale: CGFloat = 0.34
    private static let minimumScale: CGFloat = 0.3

    let barWidth: CGFloat = 3.2
    let barGap: CGFloat = 5
    /// 单根波纹线的最大高度，动画只在这个高度内缩放。
    let maximumBarHeight: CGFloat = 20

    private(set) var mode: Mode = .hidden
    private var barLayers: [CALayer] = []
    private var tintColor: CGColor = NSColor.white.cgColor

    override init() {
        super.init()
        buildBars()
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var barCount: Int { barLayers.count }

    /// 按当前 bounds 固定排布波纹槽位，右对齐到内容区右边缘。
    func relayout() {
        guard bounds.height > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let groupWidth = CGFloat(barLayers.count) * barWidth + CGFloat(max(barLayers.count - 1, 0)) * barGap
        let startX = max(bounds.minX, bounds.maxX - groupWidth)
        let midY = bounds.midY
        for (index, bar) in barLayers.enumerated() {
            let height = maximumBarHeight * Self.barWeights[index % Self.barWeights.count]
            bar.frame = CGRect(
                x: startX + CGFloat(index) * (barWidth + barGap),
                y: midY - height / 2,
                width: barWidth,
                height: height
            )
        }
        CATransaction.commit()
    }

    /// 波纹颜色跟随头像主色；nil 表示回退成白色。只换背景色，不重建槽位、不打断相位。
    func setTint(_ color: NSColor?) {
        let next = (color ?? .white).cgColor
        guard next != tintColor else { return }
        tintColor = next
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for bar in barLayers { bar.backgroundColor = next }
        CATransaction.commit()
    }

    /// 外部电平驱动（真实系统音频）：只写 transform，不挂 CA 动画、不重建槽位。
    func setLevels(_ levels: [CGFloat]) {
        guard mode == .playing, !levels.isEmpty else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in barLayers.enumerated() {
            let raw = levels[index % levels.count]
            let scale = min(max(raw, Self.minimumScale), 1)
            bar.transform = CATransform3DMakeScale(1, scale, 1)
        }
        CATransaction.commit()
    }

    func apply(mode newMode: Mode, animate: Bool) {
        guard newMode != mode || (newMode == .playing && !isPulsing) else { return }
        mode = newMode
        switch newMode {
        case .hidden:
            isHidden = true
            stopPulsing()
        case .playing:
            isHidden = false
            startPulsing(animate: animate)
        case .frozen:
            isHidden = false
            freeze()
        }
    }

    private var isPulsing: Bool {
        barLayers.first?.animationKeys()?.contains(Self.animationKey) == true
    }

    private func buildBars() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for index in 0..<Self.barSlotCount {
            let bar = CALayer()
            bar.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            bar.backgroundColor = tintColor
            bar.cornerRadius = barWidth / 2
            bar.allowsGroupOpacity = true
            bar.opacity = Float(0.55 + 0.45 * Double(Self.barWeights[index]))
            addSublayer(bar)
            barLayers.append(bar)
        }
        CATransaction.commit()
    }

    private func startPulsing(animate: Bool) {
        for bar in barLayers {
            bar.removeAnimation(forKey: Self.animationKey)
        }
        guard animate else {
            restoreFullScale()
            return
        }
        let timing = CAMediaTimingFunction(name: .easeInEaseOut)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in barLayers.enumerated() {
            let duration = Self.barDurations[index % Self.barDurations.count]
            let animation = CABasicAnimation(keyPath: "transform.scale.y")
            animation.fromValue = Self.frozenScale
            animation.toValue = 1.0
            animation.duration = duration
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = timing
            // 负偏移让每根线从确定性的相位起点开始，重建视图也不会重新对齐。
            animation.timeOffset = -duration * Double(index) / Double(barLayers.count)
            bar.add(animation, forKey: Self.animationKey)
        }
        CATransaction.commit()
    }

    private func freeze() {
        for bar in barLayers {
            bar.removeAnimation(forKey: Self.animationKey)
        }
        setScale(Self.frozenScale)
    }

    private func stopPulsing() {
        for bar in barLayers {
            bar.removeAnimation(forKey: Self.animationKey)
        }
        setScale(1)
    }

    private func restoreFullScale() { setScale(1) }

    private func setScale(_ scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for bar in barLayers {
            bar.transform = CATransform3DMakeScale(1, scale, 1)
        }
        CATransaction.commit()
    }
}
