import AppKit
import Combine
import CoreGraphics
import CoreImage
import SwiftUI

final class IslandWindowController: NSWindowController {
    private let hostingView: NSHostingView<AnyView>
    private(set) var isExpanded = false

    // gooey 窗口（宽，承载模糊融合层，忽略鼠标事件）
    private let gooeyWindow: NSPanel
    private let gooeyContainer = CALayer()
    private let topBarLayer = CALayer()
    private let mainBodyLayer = CAShapeLayer()
    private var blurFilter: CIFilter?

    // content 窗口（窄，只覆盖图标区域，接收鼠标事件）
    private let contentWindow: NSPanel

    // 紧凑音乐层：独立透明面板，严格覆盖刘海带，忽略鼠标事件
    private let compactWindow: NSPanel
    private var compactContainerView: NSView?
    private let compactBandLayer = CAShapeLayer()
    private let compactMediaView = CompactMediaView(frame: .zero)
    private var compactBand: CompactBand?
    private var compactContentWanted = false
    private var audioTapUnavailable = false
    private var didAskForAudioPermission = false
    private static let compactOpacityKey = "compact.opacity"

    private var cancellables = Set<AnyCancellable>()
    private var pendingRebuild = false
    private var transitionID = UUID()
    private var isTransitioning = false
    private var isEnabled = true
    /// 自定义面板打开期间锁定展开态：真实岛屿作为实时预览，不随鼠标离开收起。
    private var isLivePreviewPinned = false
    /// 预览时「收起态 / 展开态」分段控件的选择：收起态下真实岛屿跟着收起。
    private var livePreviewWantsExpanded = true
    static weak var shared: IslandWindowController?

    init() {
        let settings = SettingsStore.shared
        let height = Self.contentHeight(for: settings)
        let topBarHeight = settings.topBarHeight
        let topBarWidth = settings.topBarWidth
        let expandedWidth = settings.expandedWidth
        let totalHeight = height + topBarHeight

        // === gooey 窗口：宽，承载模糊融合，忽略鼠标事件 ===
        let gooeyFrame = NSRect(x: 0, y: 0, width: topBarWidth, height: totalHeight)
        gooeyWindow = NSPanel(contentRect: gooeyFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        gooeyWindow.isOpaque = false
        gooeyWindow.backgroundColor = .clear
        gooeyWindow.hasShadow = false
        gooeyWindow.level = .statusBar
        gooeyWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        gooeyWindow.ignoresMouseEvents = true
        gooeyWindow.alphaValue = 0
        gooeyWindow.animationBehavior = .none
        gooeyWindow.isReleasedWhenClosed = false

        let gooeyView = NSView(frame: gooeyFrame)
        gooeyView.wantsLayer = true
        gooeyView.layer?.backgroundColor = NSColor.clear.cgColor

        gooeyContainer.frame = CGRect(x: 0, y: 0, width: topBarWidth, height: totalHeight)

        let blur = CIFilter(name: "CIGaussianBlur")!
        blur.setValue(settings.gooeyBlurRadius, forKey: kCIInputRadiusKey)
        blurFilter = blur

        let matrix = CIFilter(name: "CIColorMatrix")!
        matrix.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
        matrix.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 19), forKey: "inputAVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: -9), forKey: "inputBiasVector")

        gooeyContainer.filters = [blur, matrix]
        gooeyView.layer?.addSublayer(gooeyContainer)

        topBarLayer.frame = Self.topBarFrame(width: Self.compactWidth(for: settings), bodyHeight: height, topBarWidth: topBarWidth, topBarHeight: topBarHeight)
        topBarLayer.backgroundColor = NSColor.black.cgColor
        gooeyContainer.addSublayer(topBarLayer)

        let initialBodyWidth = Self.compactWidth(for: settings)
        let initialBodyHeight = settings.compactHeight
        let bodyX = (topBarWidth - initialBodyWidth) / 2
        let initialRect = CGRect(x: bodyX, y: height - initialBodyHeight, width: initialBodyWidth, height: initialBodyHeight)
        mainBodyLayer.frame = CGRect(x: 0, y: 0, width: topBarWidth, height: totalHeight)
        mainBodyLayer.path = Self.islandPath(rect: initialRect, bottomRadius: settings.compactCornerRadius)
        mainBodyLayer.fillColor = NSColor.black.cgColor
        gooeyContainer.addSublayer(mainBodyLayer)

        gooeyWindow.contentView = gooeyView

        // === content 窗口：窄，只覆盖图标区域，接收鼠标事件 ===
        let contentFrame = NSRect(x: 0, y: 0, width: expandedWidth, height: height)
        contentWindow = NSPanel(contentRect: contentFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        contentWindow.isOpaque = false
        contentWindow.backgroundColor = .clear
        contentWindow.hasShadow = false
        contentWindow.level = .statusBar
        contentWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentWindow.ignoresMouseEvents = true
        contentWindow.alphaValue = 0
        contentWindow.animationBehavior = .none
        contentWindow.isReleasedWhenClosed = false

        let root = IslandRootView()
            .environmentObject(AppStore.shared)
            .environmentObject(settings)
            .environmentObject(IslandViewModel.shared)
            .environmentObject(MediaPlayerStore.shared)
            .environmentObject(SystemMetricsStore.shared)

        let host = NSHostingView(rootView: AnyView(root))
        host.translatesAutoresizingMaskIntoConstraints = false
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        host.alphaValue = 0
        hostingView = host

        let contentContainer = NSView(frame: contentFrame)
        contentContainer.wantsLayer = true
        contentContainer.layer?.backgroundColor = NSColor.clear.cgColor
        contentContainer.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            host.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            host.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
        ])
        contentWindow.contentView = contentContainer

        // === 紧凑音乐层：只覆盖刘海带的透明面板，不参与 gooey 滤镜 ===
        compactWindow = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        compactWindow.isOpaque = false
        compactWindow.backgroundColor = .clear
        compactWindow.hasShadow = false
        compactWindow.level = .statusBar
        compactWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        compactWindow.ignoresMouseEvents = true
        compactWindow.animationBehavior = .none
        compactWindow.isReleasedWhenClosed = false

        let compactContainer = NSView(frame: .zero)
        compactContainer.wantsLayer = true
        compactContainer.layer?.backgroundColor = NSColor.clear.cgColor
        compactContainer.layer?.masksToBounds = true
        // 临时观察用：紧凑带主体改成红色，方便看清轮廓与圆角
        compactBandLayer.fillColor = NSColor.systemRed.cgColor
        compactContainer.layer?.addSublayer(compactBandLayer)
        compactMediaView.frame = .zero
        compactContainer.addSubview(compactMediaView)
        compactWindow.contentView = compactContainer
        compactContainerView = compactContainer

        // NSWindowController 绑定 gooey 窗口（主窗口）
        super.init(window: gooeyWindow)
        Self.shared = self
        attachContentWindow()
        positionCompact()
        setupLayoutObservers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupLayoutObservers() {
        let s = SettingsStore.shared
        let layoutChanges: [AnyPublisher<Void, Never>] = [
            s.$iconSize.map { _ in () }.eraseToAnyPublisher(),
            s.$iconSpacing.map { _ in () }.eraseToAnyPublisher(),
            s.$contentPadding.map { _ in () }.eraseToAnyPublisher(),
            s.$contentTopPadding.map { _ in () }.eraseToAnyPublisher(),
            s.$bottomPadding.map { _ in () }.eraseToAnyPublisher(),
            s.$compactWidth.map { _ in () }.eraseToAnyPublisher(),
            s.$compactHeight.map { _ in () }.eraseToAnyPublisher(),
            s.$topBarHeight.map { _ in () }.eraseToAnyPublisher(),
            s.$compactBandAutoSize.map { _ in () }.eraseToAnyPublisher(),
            s.$compactBandWidth.map { _ in () }.eraseToAnyPublisher(),
            s.$compactBandHeight.map { _ in () }.eraseToAnyPublisher(),
            s.$compactBandTopRadius.map { _ in () }.eraseToAnyPublisher(),
            s.$compactBandBottomRadius.map { _ in () }.eraseToAnyPublisher(),
            s.$compactBandYOffset.map { _ in () }.eraseToAnyPublisher(),
            // 圆角画在 gooey 图层 path 上，不重建不换形状；自定义面板里拖圆角滑条
            // 时曾经不生效，就是漏了这三项。
            s.$compactCornerRadius.map { _ in () }.eraseToAnyPublisher(),
            s.$expandedCornerRadius.map { _ in () }.eraseToAnyPublisher(),
            s.$topBarYOffset.map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(layoutChanges)
        .debounce(for: .seconds(0.3), scheduler: RunLoop.main)
        .sink { [weak self] _ in self?.rebuildLayout() }
        .store(in: &cancellables)
        s.$columns
            .debounce(for: .seconds(0.3), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildLayout() }
            .store(in: &cancellables)
        s.$gooeyBlurRadius
            .debounce(for: .seconds(0.3), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildLayout() }
            .store(in: &cancellables)
        AppStore.shared.$apps
            .debounce(for: .seconds(0.3), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildLayout() }
            .store(in: &cancellables)
        s.$mediaPlayerBundleID
            .removeDuplicates()
            .map { _ in () }
            .debounce(for: .seconds(0.15), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildLayout() }
            .store(in: &cancellables)
        // 刘海加宽只跟随「有没有音乐内容」这一个布尔值，切歌刷新文案不会重建窗口。
        Publishers.CombineLatest(MediaPlayerStore.shared.$playbackState, MediaPlayerStore.shared.$track)
            .map { _ in MediaPlayerStore.shared.hasCompactMedia }
            .removeDuplicates()
            .map { _ in () }
            .debounce(for: .seconds(0.15), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildLayout() }
            .store(in: &cancellables)
        // 头像、取色与波纹状态属于纯内容更新：只改合成层属性，不动几何、不重置波纹相位。
        Publishers.CombineLatest4(
            MediaPlayerStore.shared.$track,
            MediaPlayerStore.shared.$avatarImage,
            MediaPlayerStore.shared.$avatarTint,
            MediaPlayerStore.shared.$playbackState
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.updateCompactMediaContents() }
        .store(in: &cancellables)
    }

    private static func contentHeight(for settings: SettingsStore) -> CGFloat {
        settings.expandedHeight
    }

    /// 收起态紧凑带：几何全部由刘海推导，黑色主体和音乐内容层共用同一个结果。
    private static func measuredCompactBand(for settings: SettingsStore) -> CompactBand? {
        guard MediaPlayerStore.shared.hasCompactMedia else { return nil }
        return NotchDetector.compactBand(
            notch: NotchDetector.current(),
            baseWidth: settings.compactWidth,
            limitWidth: settings.topBarWidth - 24,
            contentWidth: CompactMediaView.contentWidth,
            widthOverride: settings.compactBandAutoSize ? nil : settings.compactBandWidth,
            heightOverride: settings.compactBandAutoSize ? nil : settings.compactBandHeight,
            topRadiusOverride: settings.compactBandTopRadius > 0 ? settings.compactBandTopRadius : nil,
            bottomRadiusOverride: settings.compactBandBottomRadius > 0 ? settings.compactBandBottomRadius : nil,
            verticalOffset: settings.compactBandYOffset
        )
    }

    private static func compactWidth(for settings: SettingsStore) -> CGFloat {
        measuredCompactBand(for: settings)?.frame.width ?? settings.compactWidth
    }

    // MARK: - 紧凑音乐层

    /// 把紧凑带窗口对齐到刘海几何：窗口本身就是刘海带，内容不可能溢出到屏幕外。
    private func applyCompactBand() {
        let settings = SettingsStore.shared
        guard let band = Self.measuredCompactBand(for: settings) else {
            compactBand = nil
            return
        }
        compactBand = band
        if compactWindow.frame != band.frame {
            compactWindow.setFrame(band.frame, display: false)
        }
        guard let container = compactContainerView else { return }
        let bounds = NSRect(origin: .zero, size: band.frame.size)
        if container.frame != bounds { container.frame = bounds }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        compactBandLayer.frame = bounds
        compactBandLayer.path = Self.notchPath(rect: bounds, topRadius: band.topRadius, bottomRadius: band.bottomRadius)
        CATransaction.commit()
        if compactMediaView.frame != bounds { compactMediaView.frame = bounds }
    }

    /// 只更新头像与波纹状态，不重建窗口、不改几何。
    private func updateCompactMediaContents() {
        let store = MediaPlayerStore.shared
        let mode: WaveformLayer.Mode
        switch (store.track != nil, store.playbackState) {
        case (true, .playing): mode = .playing
        case (true, .paused): mode = .frozen
        default: mode = .hidden
        }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let audioDriven = configureAudioTap(
            mode: mode,
            reduceMotion: reduceMotion,
            showsCompact: !isExpanded && isEnabled && compactBand != nil
        )
        compactMediaView.update(
            image: store.avatarImage,
            mode: mode,
            tint: store.avatarTint,
            animates: mode == .playing && !reduceMotion && !audioDriven
        )
    }

    /// 只有收起态真的在播放时才开系统音频采集；返回是否由真实电平驱动波纹。
    @discardableResult
    private func configureAudioTap(mode: WaveformLayer.Mode, reduceMotion: Bool, showsCompact: Bool) -> Bool {
        let tap = SystemAudioTap.shared
        guard mode == .playing, !reduceMotion, showsCompact, !audioTapUnavailable else {
            tap.stop()
            return false
        }
        guard SystemAudioTap.isAuthorized else {
            if !didAskForAudioPermission {
                didAskForAudioPermission = true
                SystemAudioTap.requestPermission()
            }
            return false
        }
        tap.onLevels = { [weak self] levels in
            guard let self, !self.isExpanded else { return }
            self.compactMediaView.setWaveformLevels(levels)
        }
        tap.onUnavailable = { [weak self] in
            guard let self else { return }
            self.audioTapUnavailable = true
            self.updateCompactMediaContents()
        }
        tap.start()
        return true
    }

    private func syncCompactVisibility(
        duration: TimeInterval = 0,
        timing: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeOut)
    ) {
        applyCompactBand()
        updateCompactMediaContents()
        setCompactVisible(!isExpanded && isEnabled && compactBand != nil, duration: duration, timing: timing)
    }

    private func setCompactVisible(_ visible: Bool, duration: TimeInterval, timing: CAMediaTimingFunction) {
        compactContentWanted = visible
        guard let layer = compactContainerView?.layer else {
            compactWindow.orderOut(nil)
            return
        }
        let target: Float = visible ? 1 : 0
        // 从当前呈现值继续过渡，反复进出触发区不会跳变。
        let from = layer.presentation()?.opacity ?? layer.opacity
        layer.removeAnimation(forKey: Self.compactOpacityKey)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = target
        CATransaction.commit()
        if visible {
            compactWindow.orderFrontRegardless()
        }
        if duration > 0, abs(from - target) >= 0.004 {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = from
            animation.toValue = target
            animation.duration = duration
            animation.timingFunction = timing
            layer.add(animation, forKey: Self.compactOpacityKey)
        }
        guard !visible else { return }
        let transition = transitionID
        DispatchQueue.main.asyncAfter(deadline: .now() + max(duration, 0)) { [weak self] in
            guard let self, self.transitionID == transition, !self.compactContentWanted else { return }
            self.compactWindow.orderOut(nil)
        }
    }

    private func rebuildLayout() {
        guard isEnabled else { pendingRebuild = true; return }
        guard !isTransitioning else {
            pendingRebuild = true
            return
        }
        if isExpanded {
            refreshForCurrentScreen()
            return
        }
        let settings = SettingsStore.shared
        let height = Self.contentHeight(for: settings)
        let topBarHeight = settings.topBarHeight
        let topBarWidth = settings.topBarWidth
        let expandedWidth = settings.expandedWidth
        let totalHeight = height + topBarHeight

        blurFilter?.setValue(settings.gooeyBlurRadius, forKey: kCIInputRadiusKey)
        gooeyContainer.frame = CGRect(x: 0, y: 0, width: topBarWidth, height: totalHeight)
        topBarLayer.removeAllAnimations()
        topBarLayer.frame = Self.topBarFrame(width: Self.compactWidth(for: settings), bodyHeight: height, topBarWidth: topBarWidth, topBarHeight: topBarHeight)
        mainBodyLayer.frame = CGRect(x: 0, y: 0, width: topBarWidth, height: totalHeight)

        let initialBodyWidth = Self.compactWidth(for: settings)
        let initialBodyHeight = settings.compactHeight
        let bodyX = (topBarWidth - initialBodyWidth) / 2
        let compactRect = CGRect(x: bodyX, y: height - initialBodyHeight, width: initialBodyWidth, height: initialBodyHeight)
        mainBodyLayer.path = Self.islandPath(rect: compactRect, bottomRadius: settings.compactCornerRadius)

        // 更新 content 窗口尺寸
        contentWindow.setFrame(NSRect(x: 0, y: 0, width: expandedWidth, height: height), display: true)

        positionCompact()
    }

    func testExpand() {
        let settings = SettingsStore.shared
        if isExpanded {
            hideIsland()
            DispatchQueue.main.asyncAfter(deadline: .now() + settings.collapseDuration + 0.05) { [weak self] in
                self?.performTestExpand()
            }
        } else {
            performTestExpand()
        }
    }

    private func performTestExpand() {
        let settings = SettingsStore.shared
        showIsland()
        let holdTime = settings.expandDuration + settings.revealDelay + 0.8
        DispatchQueue.main.asyncAfter(deadline: .now() + holdTime) { [weak self] in
            self?.hideIsland()
        }
    }

    /// 打开自定义面板：强制展开真实岛屿，作为实时预览。
    func beginLivePreview() {
        guard !isLivePreviewPinned else { return }
        isLivePreviewPinned = true
        livePreviewWantsExpanded = true
        showIsland()
    }

    /// 关闭自定义面板：解除锁定，若仍是展开态就收起。
    func endLivePreview() {
        guard isLivePreviewPinned else { return }
        livePreviewWantsExpanded = true
        isLivePreviewPinned = false
        if isExpanded {
            hideIsland()
        }
    }

    /// 预览面板里切换「收起态」：真实岛屿跟着收起，方便直接看刘海带尺寸；
    /// 切回「展开态」再展开回来。面板没开时调用无效。
    func setLivePreviewExpanded(_ expanded: Bool) {
        guard expanded != livePreviewWantsExpanded else { return }
        livePreviewWantsExpanded = expanded
        guard isLivePreviewPinned else { return }
        if expanded {
            showIsland()
        } else {
            hideIsland()
        }
    }

    func showIsland() {
        guard !isExpanded else { return }
        // 预览锁定期间只有预览明确要展开时才允许展开，防悬停探测把收起态又弹开
        guard !isLivePreviewPinned || livePreviewWantsExpanded else { return }
        let settings = SettingsStore.shared
        isEnabled = true
        if pendingRebuild && !isTransitioning {
            pendingRebuild = false
            rebuildLayout()
        }
        transitionID = UUID()
        let transition = transitionID
        isExpanded = true
        isTransitioning = true
        SystemMetricsStore.shared.setActive(true)
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : settings.expandDuration
        let delay = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : settings.revealDelay

        let (gooeyRect, contentRect) = expandedFrames()
        gooeyWindow.setFrame(gooeyRect, display: true)
        contentWindow.setFrame(contentRect, display: true)

        gooeyWindow.alphaValue = 1
        contentWindow.ignoresMouseEvents = false
        contentWindow.alphaValue = 1
        hostingView.alphaValue = 0

        attachContentWindow()
        gooeyWindow.orderFrontRegardless()
        contentWindow.orderFrontRegardless()

        animateExpand(duration: duration)
        fadeContent(visible: true, delay: delay)
        syncCompactVisibility(duration: duration, timing: settings.expandTimingFunction)
        ClickProbe.log("内容窗口 frame=\(contentRect) 图标=\(settings.iconSize) 间距=\(settings.iconSpacing) 列=\(settings.columns) 左右边距=\(settings.contentPadding) 顶部=\(settings.effectiveContentTopPadding)")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.transitionID == transition, self.isExpanded else { return }
            IslandViewModel.shared.isExpanded = true
        }
        finishTransition(after: duration, id: transition)
    }

    func hideIsland() {
        guard isExpanded else { return }
        // 自定义面板开着：真实岛屿是实时预览，只有预览明确要收起时才允许收起
        guard !isLivePreviewPinned || !livePreviewWantsExpanded else { return }
        let settings = SettingsStore.shared
        transitionID = UUID()
        let transition = transitionID
        isExpanded = false
        isTransitioning = true
        SystemMetricsStore.shared.setActive(false)
        let duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : settings.collapseDuration
        IslandViewModel.shared.isExpanded = false
        TooltipNSView.dismissActiveTip()
        contentWindow.ignoresMouseEvents = true
        fadeContent(visible: false, delay: 0)
        animateCollapse(duration: duration)
        syncCompactVisibility(duration: duration, timing: settings.collapseTimingFunction)
        finishTransition(after: duration, id: transition)
    }

    private func finishTransition(after duration: TimeInterval, id: UUID) {
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self.transitionID == id, self.isEnabled else { return }
            self.isTransitioning = false
            if !self.isExpanded {
                self.positionCompact()
            }
            if self.pendingRebuild {
                self.pendingRebuild = false
                self.rebuildLayout()
            }
        }
    }

    func hideIslandImmediately() {
        isEnabled = false
        transitionID = UUID()
        isTransitioning = false
        isExpanded = false
        SystemMetricsStore.shared.setActive(false)
        IslandViewModel.shared.isExpanded = false
        TooltipNSView.dismissActiveTip()
        mainBodyLayer.removeAllAnimations()
        topBarLayer.removeAllAnimations()
        setCompactVisible(false, duration: 0, timing: CAMediaTimingFunction(name: .easeOut))
        SystemAudioTap.shared.stop()
        hostingView.alphaValue = 0
        contentWindow.ignoresMouseEvents = true
        contentWindow.alphaValue = 0
        contentWindow.orderOut(nil)
        gooeyWindow.alphaValue = 0
        gooeyWindow.orderOut(nil)
    }

    func refreshForCurrentScreen() {
        guard isEnabled else { return }
        transitionID = UUID()
        isTransitioning = false
        let settings = SettingsStore.shared
        let height = Self.contentHeight(for: settings)
        let topBarHeight = settings.topBarHeight
        let topBarWidth = settings.topBarWidth
        let expandedWidth = settings.expandedWidth
        let totalHeight = height + topBarHeight

        blurFilter?.setValue(settings.gooeyBlurRadius, forKey: kCIInputRadiusKey)
        gooeyContainer.frame = CGRect(x: 0, y: 0, width: topBarWidth, height: totalHeight)
        topBarLayer.removeAllAnimations()
        mainBodyLayer.removeAllAnimations()
        topBarLayer.frame = Self.topBarFrame(
            width: isExpanded ? topBarWidth : Self.compactWidth(for: settings),
            bodyHeight: height,
            topBarWidth: topBarWidth,
            topBarHeight: topBarHeight
        )
        mainBodyLayer.frame = CGRect(x: 0, y: 0, width: topBarWidth, height: totalHeight)

        if isExpanded {
            SystemMetricsStore.shared.setActive(true)
            let frames = expandedFrames()
            let expandedRect = CGRect(x: (topBarWidth - expandedWidth) / 2, y: 0, width: expandedWidth, height: height)

            attachContentWindow()
            gooeyWindow.setFrame(frames.gooey, display: false)
            contentWindow.setFrame(frames.content, display: false)
            gooeyWindow.alphaValue = 1
            contentWindow.alphaValue = 1
            contentWindow.ignoresMouseEvents = false
            hostingView.alphaValue = 1
            gooeyWindow.orderFrontRegardless()
            contentWindow.orderFrontRegardless()
            mainBodyLayer.path = Self.islandPath(rect: expandedRect, bottomRadius: settings.expandedCornerRadius)
            syncCompactVisibility()
            IslandViewModel.shared.isExpanded = true
        } else {
            SystemMetricsStore.shared.setActive(false)
            let initialBodyWidth = Self.compactWidth(for: settings)
            let initialBodyHeight = settings.compactHeight
            let bodyX = (topBarWidth - initialBodyWidth) / 2
            let compactRect = CGRect(x: bodyX, y: height - initialBodyHeight, width: initialBodyWidth, height: initialBodyHeight)
            mainBodyLayer.path = Self.islandPath(rect: compactRect, bottomRadius: settings.compactCornerRadius)
            contentWindow.setFrame(NSRect(x: 0, y: 0, width: expandedWidth, height: height), display: false)
            positionCompact()
        }
    }

    private func attachContentWindow() {
        guard contentWindow.parent !== gooeyWindow else { return }
        contentWindow.parent?.removeChildWindow(contentWindow)
        gooeyWindow.addChildWindow(contentWindow, ordered: .above)
    }

    private func positionCompact() {
        guard isEnabled else { return }
        let settings = SettingsStore.shared
        let notch = NotchDetector.current()
        let height = Self.contentHeight(for: settings)
        let topBarHeight = settings.topBarHeight
        let topBarWidth = settings.topBarWidth
        let expandedWidth = settings.expandedWidth
        let windowBottom = windowBottom(for: notch, bodyHeight: height, topBarHeight: topBarHeight, yOffset: settings.topBarYOffset)

        let gooeyRect = NSRect(x: centeredX(anchor: notch.anchor.x, width: topBarWidth, in: notch.screenFrame), y: windowBottom, width: topBarWidth, height: height + topBarHeight)
        gooeyWindow.setFrame(gooeyRect, display: false)
        gooeyWindow.alphaValue = 1
        gooeyWindow.orderFrontRegardless()

        let contentRect = NSRect(x: centeredX(anchor: notch.anchor.x, width: expandedWidth, in: notch.screenFrame), y: windowBottom, width: expandedWidth, height: height)
        contentWindow.setFrame(contentRect, display: false)
        contentWindow.ignoresMouseEvents = true
        contentWindow.alphaValue = 0
        hostingView.alphaValue = 0
        contentWindow.orderOut(nil)
        syncCompactVisibility()
    }

    private func expandedFrames() -> (gooey: NSRect, content: NSRect) {
        let settings = SettingsStore.shared
        let notch = NotchDetector.current()
        let height = Self.contentHeight(for: settings)
        let topBarHeight = settings.topBarHeight
        let topBarWidth = settings.topBarWidth
        let expandedWidth = settings.expandedWidth
        let windowBottom = windowBottom(for: notch, bodyHeight: height, topBarHeight: topBarHeight, yOffset: settings.topBarYOffset)

        let gooey = NSRect(x: centeredX(anchor: notch.anchor.x, width: topBarWidth, in: notch.screenFrame), y: windowBottom, width: topBarWidth, height: height + topBarHeight)
        let content = NSRect(x: centeredX(anchor: notch.anchor.x, width: expandedWidth, in: notch.screenFrame), y: windowBottom, width: expandedWidth, height: height)
        return (gooey, content)
    }

    private func windowBottom(
        for notch: NotchArea, bodyHeight: CGFloat, topBarHeight: CGFloat, yOffset: CGFloat
    ) -> CGFloat {
        guard notch.topInset > 0 else {
            // 无刘海屏：把整个窗口放在屏幕顶部以内，避免沿用刘海偏移后出屏。
            return notch.screenFrame.maxY - bodyHeight - topBarHeight
        }
        return notch.frame.minY - bodyHeight + yOffset
    }

    private func centeredX(anchor: CGFloat, width: CGFloat, in screenFrame: CGRect) -> CGFloat {
        let proposed = anchor - width / 2
        return max(screenFrame.minX, min(proposed, screenFrame.maxX - width))
    }

    /// 顶部融合条始终以岛屿中心为锚点，避免宽度变化时向某一侧漂移。
    private static func topBarFrame(
        width: CGFloat,
        bodyHeight: CGFloat,
        topBarWidth: CGFloat,
        topBarHeight: CGFloat
    ) -> CGRect {
        let clampedWidth = min(max(width, 1), topBarWidth)
        return CGRect(
            x: (topBarWidth - clampedWidth) / 2,
            y: bodyHeight,
            width: clampedWidth,
            height: topBarHeight
        )
    }

    private func fadeContent(visible: Bool, delay: TimeInterval) {
        let settings = SettingsStore.shared
        let transition = transitionID
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.transitionID == transition, self.isEnabled else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : (visible ? settings.contentFadeInDuration : settings.contentFadeOutDuration)
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.hostingView.animator().alphaValue = visible ? 1 : 0
            }
        }
    }

    private static func islandPath(rect: CGRect, bottomRadius: CGFloat = 32) -> CGPath {
        let bottomRadius = min(max(bottomRadius, 0), min(rect.width / 2, rect.height))
        let path = CGMutablePath()
        let left = rect.minX
        let right = rect.maxX
        let top = rect.maxY
        let bottom = rect.minY

        path.move(to: CGPoint(x: left + bottomRadius, y: bottom))
        path.addLine(to: CGPoint(x: right - bottomRadius, y: bottom))
        Self.appendSmoothCorner(
            path,
            from: CGPoint(x: right - bottomRadius, y: bottom),
            to: CGPoint(x: right, y: bottom + bottomRadius),
            corner: CGPoint(x: right, y: bottom),
            radius: bottomRadius
        )
        path.addLine(to: CGPoint(x: right, y: top))
        path.addLine(to: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: left, y: bottom + bottomRadius))
        Self.appendSmoothCorner(
            path,
            from: CGPoint(x: left, y: bottom + bottomRadius),
            to: CGPoint(x: left + bottomRadius, y: bottom),
            corner: CGPoint(x: left, y: bottom),
            radius: bottomRadius
        )
        path.closeSubpath()
        return path
    }

    /// 追加一段 90°「连续圆角」（Apple 风格，替代生硬的四分之一圆弧）：
    /// 用两段三次贝塞尔在角平分线上相接，入边/出边端曲率为 0，与直边自然衔接，
    /// 横向延伸出的端角因此是一条平滑肩线，而不是突然翻起的小圆弧。
    /// radius <= 0.5 时退化为直线拐角。
    private static func appendSmoothCorner(
        _ path: CGMutablePath,
        from start: CGPoint,
        to end: CGPoint,
        corner: CGPoint,
        radius: CGFloat
    ) {
        guard radius > 0.5 else {
            path.addLine(to: corner)
            path.addLine(to: end)
            return
        }
        // 两条边指向直角点的单位向量。
        let uStart = CGPoint(x: (corner.x - start.x) / radius, y: (corner.y - start.y) / radius)
        let uEnd = CGPoint(x: (corner.x - end.x) / radius, y: (corner.y - end.y) / radius)
        // 拐点落在角平分线上（t 为沿两轴的偏移，须 < radius/2 保证控制点不交叉）。
        let t = radius * 0.30
        // 贴边手柄长度（f + 2t < radius）。
        let f = radius * 0.30
        let mid = CGPoint(
            x: corner.x - t * (uStart.x + uEnd.x),
            y: corner.y - t * (uStart.y + uEnd.y)
        )
        path.addCurve(
            to: mid,
            control1: CGPoint(x: start.x + f * uStart.x, y: start.y + f * uStart.y),
            control2: CGPoint(x: mid.x - t * (uStart.x - uEnd.x), y: mid.y - t * (uStart.y - uEnd.y))
        )
        path.addCurve(
            to: end,
            control1: CGPoint(x: mid.x + t * (uStart.x - uEnd.x), y: mid.y + t * (uStart.y - uEnd.y)),
            control2: CGPoint(x: end.x + f * uEnd.x, y: end.y + f * uEnd.y)
        )
    }

    /// 收起态顶部可用小圆角平滑过渡到屏幕边缘；默认 topRadius=0 时保持贯通。
    /// 底角（横向延伸部分的端角）使用连续圆角，与原生刘海的平滑肩线一致。
    private static func notchPath(rect: CGRect, topRadius: CGFloat, bottomRadius: CGFloat) -> CGPath {
        let left = rect.minX, right = rect.maxX
        // 略微越过 view 顶边，避免屏幕顶边出现抗锯齿细缝；窗口本身仍裁在屏幕范围内。
        let top = rect.maxY + 0.5
        let floorY = rect.minY
        let topRadius = min(max(topRadius, 0), min(rect.width / 2, rect.height))
        let radius = min(max(bottomRadius, 0), min(rect.width / 2, rect.height))
        let path = CGMutablePath()
        path.move(to: CGPoint(x: left + topRadius, y: top))
        path.addLine(to: CGPoint(x: right - topRadius, y: top))
        Self.appendSmoothCorner(
            path,
            from: CGPoint(x: right - topRadius, y: top),
            to: CGPoint(x: right, y: top - topRadius),
            corner: CGPoint(x: right, y: top),
            radius: topRadius
        )
        path.addLine(to: CGPoint(x: right, y: floorY + radius))
        Self.appendSmoothCorner(
            path,
            from: CGPoint(x: right, y: floorY + radius),
            to: CGPoint(x: right - radius, y: floorY),
            corner: CGPoint(x: right, y: floorY),
            radius: radius
        )
        path.addLine(to: CGPoint(x: left + radius, y: floorY))
        Self.appendSmoothCorner(
            path,
            from: CGPoint(x: left + radius, y: floorY),
            to: CGPoint(x: left, y: floorY + radius),
            corner: CGPoint(x: left, y: floorY),
            radius: radius
        )
        path.addLine(to: CGPoint(x: left, y: top - topRadius))
        Self.appendSmoothCorner(
            path,
            from: CGPoint(x: left, y: top - topRadius),
            to: CGPoint(x: left + topRadius, y: top),
            corner: CGPoint(x: left, y: top),
            radius: topRadius
        )
        path.closeSubpath()
        return path
    }

    private func animateExpand(duration: TimeInterval) {
        animateBody(expanded: true, duration: duration)
    }

    private func animateCollapse(duration: TimeInterval) {
        animateBody(expanded: false, duration: duration)
    }

    private func animateBody(expanded: Bool, duration: TimeInterval) {
        let settings = SettingsStore.shared
        let topBarWidth = settings.topBarWidth
        let height = Self.contentHeight(for: settings)
        let width = expanded ? settings.expandedWidth : Self.compactWidth(for: settings)
        let bodyHeight = expanded ? height : settings.compactHeight
        let toRect = CGRect(x: (topBarWidth - width) / 2, y: height - bodyHeight,
                            width: width, height: bodyHeight)
        let path = Self.islandPath(rect: toRect, bottomRadius: expanded ? settings.expandedCornerRadius : settings.compactCornerRadius)
        // Capture presentation before removing animations so a reversal stays continuous.
        let presPath = mainBodyLayer.presentation()?.path ?? mainBodyLayer.path
        let currentTopBarWidth = topBarLayer.presentation()?.bounds.width ?? topBarLayer.bounds.width
        mainBodyLayer.removeAllAnimations()
        topBarLayer.removeAllAnimations()
        let targetTopWidth = expanded ? topBarWidth : Self.compactWidth(for: settings)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mainBodyLayer.path = path
        topBarLayer.frame = Self.topBarFrame(
            width: targetTopWidth,
            bodyHeight: height,
            topBarWidth: topBarWidth,
            topBarHeight: settings.topBarHeight
        )
        CATransaction.commit()
        guard duration > 0 else { return }

        let timing = expanded ? settings.expandTimingFunction : settings.collapseTimingFunction
        let topBarAnim = CABasicAnimation(keyPath: "bounds.size.width")
        topBarAnim.fromValue = min(max(currentTopBarWidth, 1), topBarWidth)
        topBarAnim.toValue = targetTopWidth
        topBarAnim.duration = duration
        topBarAnim.timingFunction = timing
        topBarLayer.add(topBarAnim, forKey: "width")

        let pathAnim = CABasicAnimation(keyPath: "path")
        pathAnim.fromValue = presPath
        pathAnim.toValue = path
        pathAnim.duration = duration
        pathAnim.timingFunction = timing
        mainBodyLayer.add(pathAnim, forKey: "shape")
    }
}
