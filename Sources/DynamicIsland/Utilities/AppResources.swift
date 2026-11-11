import Foundation

enum AppResources {
    private static let bundleName = "DynamicIsland_DynamicIsland.bundle"

    static let bundle: Bundle = {
        let fileManager = FileManager.default
        let executableDirectory = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents")
                .appendingPathComponent("Resources")
                .appendingPathComponent(bundleName),
            executableDirectory.appendingPathComponent(bundleName),
            executableDirectory
                .deletingLastPathComponent()
                .appendingPathComponent("Resources")
                .appendingPathComponent(bundleName)
        ].compactMap { $0 }

        for url in candidates where fileManager.fileExists(atPath: url.path) {
            if let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return .main
    }()

    static func url(forResource name: String?, withExtension ext: String?) -> URL? {
        bundle.url(forResource: name, withExtension: ext)
    }
}
