import AppKit
import ApplicationServices
import Combine

final class AccessibilityPermission: ObservableObject {
    static let shared = AccessibilityPermission()

    @Published private(set) var isGranted: Bool
    private var didPrompt = false
    private let check: () -> Bool
    private let prompt: () -> Void
    private let showSettings: () -> Void

    init(check: @escaping () -> Bool = { AXIsProcessTrusted() },
         prompt: @escaping () -> Void = {
             let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
             _ = AXIsProcessTrustedWithOptions(options)
         },
         showSettings: @escaping () -> Void = {
             if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                 NSWorkspace.shared.open(url)
             }
         }) {
        self.check = check
        self.prompt = prompt
        self.showSettings = showSettings
        isGranted = check()
    }

    @discardableResult
    func refresh() -> Bool {
        let granted = check()
        if isGranted != granted { isGranted = granted }
        return granted
    }

    func request() {
        // The system prompt already contains its own Open Settings action.
        if !refresh(), !didPrompt {
            didPrompt = true
            prompt()
        } else {
            showSettings()
        }
    }
}
