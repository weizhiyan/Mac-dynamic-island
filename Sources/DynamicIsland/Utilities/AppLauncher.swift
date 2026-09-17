import AppKit

struct AppLauncher {
    static func launch(_ item: AppItem) {
        guard let urlString = item.path else {
            ClickProbe.log("launch \(item.name) → ❌ 没有 path")
            return
        }
        guard !ClickProbe.isDryRun else {
            ClickProbe.log("launch \(item.name) path=\(urlString) 【空跑，不真开】")
            return
        }
        let ok = NSWorkspace.shared.open(URL(fileURLWithPath: urlString))
        ClickProbe.log("launch \(item.name) path=\(urlString) 结果=\(ok)")
    }
}

/// 临时诊断：点击到底死在哪一层。定位完就删。
enum ClickProbe {
    /// `DYNAMIC_ISLAND_CLICK_DEBUG=dryrun` 时只记录、不真的启动应用，
    /// 这样可以把 18 个图标全点一遍而不会真开 18 个程序。
    static let isDryRun = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_CLICK_DEBUG"] == "dryrun"

    /// `DYNAMIC_ISLAND_NO_TIP=1` 时完全不弹提示气泡，用来验证气泡是否吃掉了点击。
    static let tipDisabled = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_NO_TIP"] == "1"

    /// `DYNAMIC_ISLAND_LEGACY_TIP=1` 复现修复前的气泡行为，用来做前后对比。
    static let legacyTip = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_LEGACY_TIP"] == "1"

    static func log(_ message: String) {
        print("[点击探针] \(message)")
        fflush(stdout)
    }
}
