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

    private var cancellables = Set<AnyCancellable>()
    private var pendingRebuild = false
    static weak var shared: IslandWindowController?

    init() {
        let settings = SettingsStore.shared
        let height = settings.expandedHeight
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

        topBarLayer.frame = CGRect(x: 0, y: height, width: topBarWidth, height: topBarHeight)
        topBarLayer.backgroundColor = NSColor.black.cgColor
        gooeyContainer.addSublayer(topBarLayer)

        let initialBodyWidth = settings.compactWidth
        let initialBodyHeight = settings.compactHeight
        let bodyX = (topBarWidth - initialBodyWidth) / 2
        let initialRect = CGRect(x: bodyX, y: height - initialBodyHeight, width: initialBodyWidth, height: initialBodyHeight)
        mainBodyLayer.frame = CGRect(x: 0, y: 0, width: topBarWidth, height: totalHeight)
        mainBodyLayer.path = CGPath(roundedRect: initialRect, cornerWidth: settings.compactCornerRadius, cornerHeight: settings.compactCornerRadius, transform: nil)
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

        // NSWindowController 绑定 gooey 窗口（主窗口）
        super.init(window: gooeyWindow)
        Self.shared = self
        positionCompact()
        setupLayoutObservers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func setupLayoutObservers() {
        let s = SettingsStore.shared
        Publishers.MergeMany(
            s.$iconSize.map { _ in () },
            s.$iconSpacing.map { _ in () },
            s.$contentPadding.map { _ in () },
            s.$contentTopPadding.map { _ in () },
            s.$bottomPadding.map { _ in () },
            s.$compactWidth.map { _ in () },
            s.$compactHeight.map { _ in () },
            s.$topBarHeight.map { _ in () }
        )
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
    }

    private func rebuildLayout() {
        guard !isExpanded else {
            pendingRebuild = true
            return
        }
        let settings = SettingsStore.shared
        let height = settings.expandedHeight
        let topBarHeight = settings.topBarHeight
        let topBarWidth = settings.topBarWidth
        let expandedWidth = settings.expandedWidth
        let totalHeight = height + topBarHeight

        blurFilter?.setValue(settings.gooeyBlurRadius, forKey: kCIInputRadiusKey)
        gooeyContainer.frame = CGRect(x: 0, y: 0, width: topBarWidth, height: totalHeight)
        topBarLayer.frame = CGRect(x: 0, y: height, width: topBarWidth, height: topBarHeight)
        mainBodyLayer.frame = CGRect(x: 0, y: 0, width: topBarWidth, height: totalHeight)

        let initialBodyWidth = settings.compactWidth
        let initialBodyHeight = settings.compactHeight
        let bodyX = (topBarWidth - initialBodyWidth) / 2
        let compactRect = CGRect(x: bodyX, y: height - initialBodyHeight, width: initialBodyWidth, height: initialBodyHeight)
        mainBodyLayer.path = CGPath(roundedRect: compactRect, cornerWidth: settings.compactCornerRadius, cornerHeight: settings.compactCornerRadius, transform: nil)

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

    func showIsland() {
        guard !isExpanded else { return }
        let settings = SettingsStore.shared
        isExpanded = true

        let (gooeyRect, contentRect) = expandedFrames()
        gooeyWindow.setFrame(gooeyRect, display: true)
        contentWindow.setFrame(contentRect, display: true)

        gooeyWindow.alphaValue = 1
        contentWindow.ignoresMouseEvents = false
        contentWindow.alphaValue = 1
        hostingView.alphaValue = 0

        gooeyWindow.orderFrontRegardless()
        contentWindow.orderFrontRegardless()

        animateExpand(duration: settings.expandDuration)
        fadeContent(visible: true, delay: settings.revealDelay)
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.revealDelay) {
            IslandViewModel.shared.isExpanded = true
        }
    }

    func hideIsland() {
        guard isExpanded else { return }
        let settings = SettingsStore.shared
        isExpanded = false
        IslandViewModel.shared.isExpanded = false
        contentWindow.ignoresMouseEvents = true
        fadeContent(visible: false, delay: 0)
        animateCollapse(duration: settings.collapseDuration)
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.collapseDuration) {
            guard !self.isExpanded else { return }
            self.positionCompact()
            if self.pendingRebuild {
                self.pendingRebuild = false
                self.rebuildLayout()
            }
        }
    }

    func hideIslandImmediately() {
        isExpanded = false
        IslandViewModel.shared.isExpanded = false
        mainBodyLayer.removeAllAnimations()
        hostingView.alphaValue = 0
        contentWindow.ignoresMouseEvents = true
        contentWindow.alphaValue = 0
        contentWindow.orderOut(nil)
        gooeyWindow.alphaValue = 0
        gooeyWindow.orderOut(nil)
    }

    private func positionCompact() {
        let settings = SettingsStore.shared
        let notch = NotchDetector.current()
        let height = settings.expandedHeight
        let topBarHeight = settings.topBarHeight
        let topBarWidth = settings.topBarWidth
        let expandedWidth = settings.expandedWidth
        let windowBottom = notch.frame.minY - height + settings.topBarYOffset

        let gooeyRect = NSRect(x: notch.anchor.x - topBarWidth / 2, y: windowBottom, width: topBarWidth, height: height + topBarHeight)
        gooeyWindow.setFrame(gooeyRect, display: false)
        gooeyWindow.alphaValue = 1
        gooeyWindow.orderFrontRegardless()

        let contentRect = NSRect(x: notch.anchor.x - expandedWidth / 2, y: windowBottom, width: expandedWidth, height: height)
        contentWindow.setFrame(contentRect, display: false)
        contentWindow.ignoresMouseEvents = true
        contentWindow.alphaValue = 0
        hostingView.alphaValue = 0
        contentWindow.orderOut(nil)
    }

    private func expandedFrames() -> (gooey: NSRect, content: NSRect) {
        let settings = SettingsStore.shared
        let notch = NotchDetector.current()
        let height = settings.expandedHeight
        let topBarHeight = settings.topBarHeight
        let topBarWidth = settings.topBarWidth
        let expandedWidth = settings.expandedWidth
        let windowBottom = notch.frame.minY - height + settings.topBarYOffset

        let gooey = NSRect(x: notch.anchor.x - topBarWidth / 2, y: windowBottom, width: topBarWidth, height: height + topBarHeight)
        let content = NSRect(x: notch.anchor.x - expandedWidth / 2, y: windowBottom, width: expandedWidth, height: height)
        return (gooey, content)
    }

    private func fadeContent(visible: Bool, delay: TimeInterval) {
        let settings = SettingsStore.shared
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = visible ? settings.contentFadeInDuration : settings.contentFadeOutDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.hostingView.animator().alphaValue = visible ? 1 : 0
            }
        }
    }

    private func islandPath(rect: CGRect, topRadius: CGFloat = 0, bottomRadius: CGFloat = 32) -> CGPath {
        let path = CGMutablePath()
        let left = rect.minX
        let right = rect.maxX
        let top = rect.maxY
        let bottom = rect.minY

        path.move(to: CGPoint(x: left + bottomRadius, y: bottom))
        path.addLine(to: CGPoint(x: right - bottomRadius, y: bottom))
        path.addQuadCurve(to: CGPoint(x: right, y: bottom + bottomRadius), control: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: right, y: top))
        path.addLine(to: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: left, y: bottom + bottomRadius))
        path.addQuadCurve(to: CGPoint(x: left + bottomRadius, y: bottom), control: CGPoint(x: left, y: bottom))
        path.closeSubpath()
        return path
    }

    private func animateExpand(duration: TimeInterval) {
        let settings = SettingsStore.shared
        let expandedWidth = settings.expandedWidth
        let topBarWidth = settings.topBarWidth
        let height = settings.expandedHeight
        let initialBodyWidth = settings.compactWidth
        let initialBodyHeight = settings.compactHeight

        mainBodyLayer.removeAllAnimations()

        let compactRect = CGRect(
            x: (topBarWidth - initialBodyWidth) / 2,
            y: height - initialBodyHeight,
            width: initialBodyWidth,
            height: initialBodyHeight
        )
        let expandedRect = CGRect(x: (topBarWidth - expandedWidth) / 2, y: 0, width: expandedWidth, height: height)

        let compactPath = CGPath(roundedRect: compactRect, cornerWidth: settings.compactCornerRadius, cornerHeight: settings.compactCornerRadius, transform: nil)
        let expandedPath = islandPath(rect: expandedRect, topRadius: 0, bottomRadius: settings.expandedCornerRadius)

        let pathAnim = CABasicAnimation(keyPath: "path")
        pathAnim.fromValue = compactPath
        pathAnim.toValue = expandedPath
        pathAnim.duration = duration
        pathAnim.timingFunction = settings.expandTimingFunction
        pathAnim.fillMode = .forwards
        pathAnim.isRemovedOnCompletion = false

        mainBodyLayer.add(pathAnim, forKey: "expandPath")
    }

    private func animateCollapse(duration: TimeInterval) {
        let settings = SettingsStore.shared
        mainBodyLayer.removeAllAnimations()
        let topBarWidth = settings.topBarWidth
        let height = settings.expandedHeight
        let initialBodyWidth = settings.compactWidth
        let initialBodyHeight = settings.compactHeight

        let presPath = mainBodyLayer.presentation()?.path ?? mainBodyLayer.path
        let toRect = CGRect(
            x: (topBarWidth - initialBodyWidth) / 2,
            y: height - initialBodyHeight,
            width: initialBodyWidth,
            height: initialBodyHeight
        )

        let pathAnim = CABasicAnimation(keyPath: "path")
        pathAnim.fromValue = presPath
        pathAnim.toValue = CGPath(roundedRect: toRect, cornerWidth: settings.compactCornerRadius, cornerHeight: settings.compactCornerRadius, transform: nil)
        pathAnim.duration = duration
        pathAnim.timingFunction = settings.collapseTimingFunction
        pathAnim.fillMode = .forwards
        pathAnim.isRemovedOnCompletion = false

        mainBodyLayer.add(pathAnim, forKey: "collapse.path")
    }
}
