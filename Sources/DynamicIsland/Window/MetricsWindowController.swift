import AppKit
import SwiftUI

final class MetricsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = MetricsWindowController()
    private let presentation = MetricsPresentation()

    private init() {
        let panel = MetricsPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 580),
                                 styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "系统状态"
        panel.minSize = NSSize(width: 480, height: 552)
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        super.init(window: panel)
        panel.contentView = NSHostingView(rootView: MetricsDetailsView(presentation: presentation))
        panel.delegate = self
        panel.center()
        NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged), name: NSWindow.didChangeOcclusionStateNotification, object: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func present(_ section: MetricsSection) {
        presentation.selection = section
        window?.title = "\(section.rawValue) · 系统状态"
        SystemMetricsStore.shared.setActive(true, consumer: "metrics-window")
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        SystemMetricsStore.shared.setActive(false, consumer: "metrics-window")
    }

    @objc private func visibilityChanged() {
        SystemMetricsStore.shared.setActive(window?.isVisible == true && window?.occlusionState.contains(.visible) == true, consumer: "metrics-window")
    }
}

private final class MetricsPanel: NSPanel {
    override func cancelOperation(_ sender: Any?) { close() }
}
