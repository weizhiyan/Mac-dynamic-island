import Foundation
import Combine

final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var apps: [AppItem] {
        didSet { saveApps() }
    }

    private let defaults = UserDefaults.standard
    private static let appsKey = "shortcutApps"

    private init() {
        apps = Self.loadApps() ?? Self.defaultApps()
        defaults.removeObject(forKey: "filterApps")
    }

    func addApps(at urls: [URL]) {
        urls.forEach { addApp(at: $0) }
        normalizeOrder()
    }

    func addApp(at url: URL) {
        let resolvedURL = url.resolvingSymlinksInPath()
        let path = resolvedURL.path
        guard !apps.contains(where: { $0.path == path }) else { return }

        let bundle = Bundle(url: resolvedURL)
        let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? resolvedURL.deletingPathExtension().lastPathComponent
        let bundleId = bundle?.bundleIdentifier
        let nextOrder = (apps.map(\.order).max() ?? -1) + 1
        apps.append(AppItem(name: displayName, bundleId: bundleId, path: path, order: nextOrder))
    }

    func moveApp(_ item: AppItem, before target: AppItem) {
        guard item.id != target.id else { return }
        var orderedApps = apps.sorted(by: { $0.order < $1.order })
        guard let sourceIndex = orderedApps.firstIndex(where: { $0.id == item.id }) else { return }

        let movedApp = orderedApps.remove(at: sourceIndex)
        guard let targetIndex = orderedApps.firstIndex(where: { $0.id == target.id }) else { return }

        orderedApps.insert(movedApp, at: targetIndex)
        apps = orderedApps.enumerated().map { index, app in
            var updated = app
            updated.order = index
            return updated
        }
    }

    /// 将应用插入目标应用之前或之后。拖拽网格使用这个方法，
    /// 这样向右拖动时可以越过目标，而不是因为“始终插到前面”原地不动。
    func moveApp(_ item: AppItem, relativeTo target: AppItem, after: Bool) {
        guard item.id != target.id else { return }
        var orderedApps = apps.sorted(by: { $0.order < $1.order })
        guard let sourceIndex = orderedApps.firstIndex(where: { $0.id == item.id }) else { return }

        let movedApp = orderedApps.remove(at: sourceIndex)
        guard let targetIndex = orderedApps.firstIndex(where: { $0.id == target.id }) else { return }
        let insertionIndex = min(targetIndex + (after ? 1 : 0), orderedApps.count)
        guard insertionIndex != sourceIndex else { return }

        orderedApps.insert(movedApp, at: insertionIndex)
        apps = orderedApps.enumerated().map { index, app in
            var updated = app
            updated.order = index
            return updated
        }
    }

    func removeApp(_ item: AppItem) {
        apps.removeAll { $0.id == item.id }
        normalizeOrder()
    }

    func visibleApps() -> [AppItem] {
        apps.sorted(by: { $0.order < $1.order })
    }

    func restoreDefaultApps() {
        apps = Self.defaultApps()
    }

    static func defaultApps() -> [AppItem] {
        [
            AppItem(name: "Safari", bundleId: "com.apple.Safari", path: "/Applications/Safari.app", order: 0),
            AppItem(name: "Mail", bundleId: "com.apple.mail", path: "/System/Applications/Mail.app", order: 1),
            AppItem(name: "Messages", bundleId: "com.apple.iChat", path: "/System/Applications/Messages.app", order: 2),
            AppItem(name: "Maps", bundleId: "com.apple.Maps", path: "/System/Applications/Maps.app", order: 3),
            AppItem(name: "Photos", bundleId: "com.apple.Photos", path: "/System/Applications/Photos.app", order: 4),
            AppItem(name: "Calendar", bundleId: "com.apple.iCal", path: "/System/Applications/Calendar.app", order: 5)
        ]
    }

    private func normalizeOrder() {
        apps = apps.sorted(by: { $0.order < $1.order }).enumerated().map { index, item in
            var updated = item
            updated.order = index
            return updated
        }
    }

    private func saveApps() {
        guard let data = try? JSONEncoder().encode(apps) else { return }
        defaults.set(data, forKey: Self.appsKey)
    }

    private static func loadApps() -> [AppItem]? {
        guard let data = UserDefaults.standard.data(forKey: appsKey),
              let apps = try? JSONDecoder().decode([AppItem].self, from: data),
              !apps.isEmpty else {
            return nil
        }
        return apps
    }

}
