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
        var fallbackControls: [AXUIElement] = []
        let deadline = Date().addingTimeInterval(1)
        while let (element, depth, insidePlayer) = stack.popLast(), visited < 1_000, Date() < deadline {
            visited += 1
            let classes = attribute(element, "AXDOMClassList") as? [String] ?? []
            let isPlayer = insidePlayer || classes.contains("bottom-player")
            if isPlayer, attribute(element, kAXRoleAttribute) as? String == kAXButtonRole,
               attribute(element, kAXEnabledAttribute) as? Bool != false {
                let name = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute]
                    .compactMap { attribute(element, $0) as? String }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                if name.contains(where: { ["暂停", "pause"].contains($0) }) { return true }
                if name.contains(where: { ["播放", "继续播放", "play", "resume"].contains($0) }),
                   AXUIElementPerformAction(element, kAXPressAction as CFString) == .success { return true }
            }
            if isPlayer, classes.contains("controls"), classes.contains("center") {
                let controls = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
                for control in controls {
                    let names = attribute(control, "AXDOMClassList") as? [String] ?? []
                    if names.contains("button"), names.contains("large"), !names.contains("disabled"),
                       attribute(control, kAXEnabledAttribute) as? Bool != false {
                        fallbackControls.append(control)
                    }
                }
            }
            guard depth < 28 else { continue }
            let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
            stack.append(contentsOf: children.map { ($0, depth + 1, isPlayer) })
        }
        for control in fallbackControls {
            if AXUIElementPerformAction(control, kAXPressAction as CFString) == .success { return true }
            for child in attribute(control, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
                if AXUIElementPerformAction(child, kAXPressAction as CFString) == .success { return true }
            }
        }
        return false
    }

    static func requestPermission() {
        AccessibilityPermission.shared.request()
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
