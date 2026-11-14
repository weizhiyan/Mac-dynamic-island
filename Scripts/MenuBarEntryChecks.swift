import AppKit

@main
struct MenuBarEntryChecks {
    static var failures = 0

    static func expect(_ label: String, _ condition: Bool) {
        print("\(condition ? "PASS" : "FAIL") \(label)")
        if !condition { failures += 1 }
    }

    static func main() {
        let suite = "DynamicIsland.MenuBarEntryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let name = MenuBarEntry.autosaveName
        let dividerKey = "NSStatusItem Preferred Position DynamicIsland.HiddenSectionDivider"
        defaults.set(false, forKey: "NSStatusItem VisibleCC \(name)")
        defaults.set(1, forKey: MenuBarEntry.migrationKey)
        defaults.set(10000.0, forKey: dividerKey)
        defaults.set(250.0, forKey: "NSStatusItem Preferred Position \(name)")
        defaults.set("com.soda.music", forKey: "mediaPlayerBundleID")

        MenuBarEntry.prepareDefaults(defaults)
        expect("Migrates legacy and Tahoe visibility together",
               defaults.bool(forKey: "NSStatusItem Visible \(name)")
               && defaults.bool(forKey: "NSStatusItem VisibleCC \(name)"))
        expect("Prepares the implicit identity before naming the item",
               defaults.bool(forKey: "NSStatusItem VisibleCC Item-0"))
        expect("Migration preserves an existing menu bar position",
               defaults.double(forKey: "NSStatusItem Preferred Position \(name)") == 250)
        expect("Preserves the stash divider and player binding",
               defaults.double(forKey: dividerKey) == 10000
               && defaults.string(forKey: "mediaPlayerBundleID") == "com.soda.music")

        defaults.set(321.0, forKey: "NSStatusItem Preferred Position \(name)")
        defaults.set(false, forKey: "NSStatusItem VisibleCC \(name)")
        MenuBarEntry.prepareDefaults(defaults)
        expect("Subsequent launches preserve user placement and visibility",
               defaults.double(forKey: "NSStatusItem Preferred Position \(name)") == 321
               && !defaults.bool(forKey: "NSStatusItem VisibleCC \(name)"))
        MenuBarEntry.prepareDefaults(defaults, restoring: true)
        expect("Explicit recovery repairs visibility and placement",
               defaults.double(forKey: "NSStatusItem Preferred Position \(name)") == 0
               && defaults.bool(forKey: "NSStatusItem VisibleCC \(name)"))

        let screen = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        expect("Recognizes an actual menu bar position",
               MenuBarEntry.isInMenuBar(CGRect(x: 1600, y: 1130, width: 38, height: 39),
                                       screenFrame: screen, menuBarHeight: 39))
        expect("Rejects the observed blocked-host proxy below the screen",
               !MenuBarEntry.isInMenuBar(CGRect(x: 0, y: -22, width: 38, height: 22),
                                        screenFrame: screen, menuBarHeight: 39))
        expect("Recognizes an external display at negative coordinates",
               MenuBarEntry.isInMenuBar(CGRect(x: -400, y: 1147, width: 38, height: 22),
                                       screenFrame: CGRect(x: -2304, y: -127, width: 2304, height: 1296),
                                       menuBarHeight: 22))
        expect("Rejects empty geometry",
               !MenuBarEntry.isInMenuBar(.zero, screenFrame: screen, menuBarHeight: 39)
               && !MenuBarEntry.isInMenuBar(.null, screenFrame: screen, menuBarHeight: 39))
        exit(failures == 0 ? 0 : 1)
    }
}
