import AppKit
import SwiftUI

final class MusicPresentation: ObservableObject {
    @Published var isVisible = false
}

final class MusicWindowController: NSWindowController, NSWindowDelegate {
    static let shared = MusicWindowController()
    private let presentation = MusicPresentation()

    private init() {
        let panel = MusicPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
                               styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = "正在播放"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        super.init(window: panel)
        panel.contentView = NSHostingView(rootView: MusicDetailsView(presentation: presentation))
        panel.delegate = self
        panel.center()
        NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged), name: NSWindow.didChangeOcclusionStateNotification, object: panel)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func present() {
        presentation.isVisible = true
        MediaPlayerStore.shared.refreshNow()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) { presentation.isVisible = false }

    @objc private func visibilityChanged() {
        presentation.isVisible = window?.isVisible == true && window?.occlusionState.contains(.visible) == true
    }
}

private final class MusicPanel: NSPanel {
    override func cancelOperation(_ sender: Any?) { close() }
}
