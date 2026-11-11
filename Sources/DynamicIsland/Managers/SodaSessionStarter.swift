import AppKit
import ApplicationServices

enum SodaSessionStarter {
    static func pressPlay() -> Bool {
        guard AXIsProcessTrusted(),
              let application = NSRunningApplication.runningApplications(withBundleIdentifier: "com.soda.music").first(where: { !$0.isTerminated }) else { return false }
        let root = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 0.2)
        AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(root, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        var stack = ((attribute(root, kAXWindowsAttribute) as? [AXUIElement]) ?? []).map { ($0, 0, false) }
        var visited = 0
        let deadline = Date().addingTimeInterval(1)
        while let (element, depth, insidePlayer) = stack.popLast(), visited < 1_000, Date() < deadline {
            visited += 1
            let classes = attribute(element, "AXDOMClassList") as? [String] ?? []
            let isPlayer = insidePlayer || classes.contains("bottom-player")
            if isPlayer, classes.contains("controls"), classes.contains("center") {
                let controls = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
                for control in controls {
                    let names = attribute(control, "AXDOMClassList") as? [String] ?? []
                    if names.contains("button"), names.contains("large"), !names.contains("disabled") {
                        return AXUIElementPerformAction(control, kAXPressAction as CFString) == .success
                    }
                }
            }
            guard depth < 28 else { continue }
            let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
            stack.append(contentsOf: children.map { ($0, depth + 1, isPlayer) })
        }
        return false
    }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
