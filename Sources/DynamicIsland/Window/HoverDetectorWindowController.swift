import AppKit

final class HoverDetectorWindowController: NSWindowController {
    private let onEnter: () -> Void
    private let onLeave: () -> Void
    private let onScreenChanged: (() -> Void)?
    private let onMouseMove: ((CGFloat) -> Void)?
    private let islandFrameProvider: () -> NSRect?
    private var pollTimer: Timer?
    private var isInside = false
    private var enterWorkItem: DispatchWorkItem?
    private var leaveWorkItem: DispatchWorkItem?
    private var previewWindow: NSWindow?
    private var lastScreenFrame: CGRect?

    init(islandFrameProvider: @escaping () -> NSRect?, onEnter: @escaping () -> Void, onLeave: @escaping () -> Void, onMouseMove: ((CGFloat) -> Void)? = nil, onScreenChanged: (() -> Void)? = nil) {
        self.islandFrameProvider = islandFrameProvider
        self.onEnter = onEnter
        self.onLeave = onLeave
        self.onMouseMove = onMouseMove
        self.onScreenChanged = onScreenChanged
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.setFrame(NotchDetector.current().frame, display: true)
        super.init(window: window)
        startPolling()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        pollTimer?.invalidate()
    }

    func refreshScreenGeometry() {
        let notch = NotchDetector.current()
        window?.setFrame(notch.frame, display: true)
        if let previewWindow {
            let zone = activationZone(notch: notch)
            previewWindow.setFrame(zone, display: true)
        }
    }

    func showActivationZonePreview(duration: TimeInterval = 3.0) {
        let zone = activationZone(notch: NotchDetector.current())
        let preview: NSWindow

        if let previewWindow {
            preview = previewWindow
            preview.setFrame(zone, display: true)
        } else {
            preview = NSWindow(contentRect: zone, styleMask: .borderless, backing: .buffered, defer: false)
            preview.isOpaque = false
            preview.backgroundColor = .clear
            preview.hasShadow = false
            preview.level = .statusBar
            preview.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            preview.ignoresMouseEvents = true
            preview.isReleasedWhenClosed = false

            if let contentView = preview.contentView {
                contentView.wantsLayer = true
                contentView.layer?.backgroundColor = NSColor.red.withAlphaComponent(0.7).cgColor
                contentView.layer?.cornerRadius = 3
                contentView.layer?.cornerCurve = .continuous
            }

            previewWindow = preview
        }

        preview.alphaValue = 1
        preview.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak preview] in
            guard self?.previewWindow === preview else { return }
            preview?.orderOut(nil)
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.handleMouseMoved()
        }
        RunLoop.main.add(pollTimer!, forMode: .common)
    }

    private func handleMouseMoved() {
        let location = NSEvent.mouseLocation

        let notch = NotchDetector.current()
        if lastScreenFrame != notch.screenFrame {
            lastScreenFrame = notch.screenFrame
            onScreenChanged?()
        }
        let notchFrame = notch.frame
        let islandFrame = islandFrameProvider()
        let zone = activationZone(notch: notch)

        if let islandFrame, islandFrame.contains(location) {
            if !isInside {
                isInside = true
                leaveWorkItem?.cancel()
                leaveWorkItem = nil
                onEnter()
            }
            reportMouseMove(location: location, notchFrame: notchFrame)
            return
        }

        if zone.contains(location) {
            leaveWorkItem?.cancel()
            leaveWorkItem = nil
            if enterWorkItem == nil && !isInside {
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.enterWorkItem = nil
                    if !self.isInside {
                        self.isInside = true
                        self.onEnter()
                    }
                }
                enterWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + SettingsStore.shared.hoverEnterDelay, execute: work)
            }
            reportMouseMove(location: location, notchFrame: notchFrame)
            return
        }

        enterWorkItem?.cancel()
        enterWorkItem = nil

        if isInside {
            isInside = false
            let work = DispatchWorkItem { [weak self] in self?.onLeave() }
            leaveWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + SettingsStore.shared.hideDelay, execute: work)
        }
    }

    /// 把鼠标相对刘海中心的横向位置归一化到 [-1, 1]，供岛屿做流体跟随形变。
    private func reportMouseMove(location: CGPoint, notchFrame: NSRect) {
        guard let callback = onMouseMove else { return }
        let half = max(notchFrame.width / 2, 1)
        let normalized = max(-1, min(1, (location.x - notchFrame.midX) / half))
        callback(normalized)
    }

    private func activationZone(notch: NotchArea) -> NSRect {
        // 触发区域：水平居中于当前目标屏幕，纵向位置由 hoverZoneYOffset 控制
        // - offset = 0：紧贴刘海底部下方（鼠标可达的最高位置）
        // - offset > 0：向上移（进入刘海物理区域，鼠标可能无法到达）
        // 关键：带刘海的 MacBook 上，macOS 会限制鼠标不能进入刘海物理区域，
        // 鼠标能到达的最高 y ≈ notch.frame.minY（刘海底部），而不是屏幕物理顶部。
        let settings = SettingsStore.shared
        let width = settings.hoverZoneWidth
        let height = settings.hoverZoneHeight
        let y: CGFloat
        if notch.topInset > 0 {
            y = notch.frame.minY - height + settings.hoverZoneYOffset
        } else {
            y = notch.screenFrame.maxY - height - 1
        }
        let zone = NSRect(x: notch.anchor.x - width / 2, y: y, width: width, height: height)
        return clampedToScreen(zone, screenFrame: notch.screenFrame)
    }

    /// 把触发区收进屏幕可见范围内。
    /// 没有这层兜底时，只要屏幕高度算错（例如把无刘海的副屏当成目标屏，
    /// 刘海高度回退成 24 再叠加 hoverZoneYOffset），整条触发区就会落到屏幕上边缘之外，
    /// 鼠标永远进不去 —— 悬停彻底失效。
    private func clampedToScreen(_ zone: NSRect, screenFrame: NSRect) -> NSRect {
        let bounds = screenFrame
        guard zone.height <= bounds.height, zone.width <= bounds.width else { return zone }
        var result = zone
        // 顶端最多贴到屏幕最上面一行像素（maxY 本身不属于可见区域）
        result.origin.y = min(result.origin.y, bounds.maxY - zone.height - 1)
        result.origin.y = max(result.origin.y, bounds.minY)
        result.origin.x = min(max(result.origin.x, bounds.minX), bounds.maxX - zone.width)
        return result
    }
}
