import AppKit
import ApplicationServices
import Foundation

struct SodaMusicSnapshot: Codable, Equatable {
    let title: String
    let artist: String
    let album: String
    let isPlaying: Bool
    let progress: TimeInterval
    let duration: TimeInterval
    let bundleIdentifier: String
    let identifier: String
    var artworkBase64: String?
}

enum SodaMusicCommand: String {
    case play
    case pause
    case togglePlayPause = "toggle"
    case previous
    case next
}

enum SodaMusicActionResult {
    case success(SodaMusicSnapshot)
    case failure(String)
}

struct SodaMusicResponse: Decodable {
    var snapshot: SodaMusicSnapshot?
    var error: String?
    var confirmed: Bool?

    static func decode(_ data: Data) -> SodaMusicResponse? {
        guard var response = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        if let snapshot = response.snapshot,
           snapshot.bundleIdentifier != "com.soda.music" || snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !snapshot.progress.isFinite || !snapshot.duration.isFinite {
            response.snapshot = nil
        }
        return response
    }
}

final class SodaMusicController {
    private let bundleIdentifier = "com.soda.music"
    private let scriptURL: URL?

    init(scriptURL: URL?) { self.scriptURL = scriptURL }

    var isRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).contains { !$0.isTerminated }
    }

    func read() -> SodaMusicResponse { query(action: "state") }

    func send(_ command: SodaMusicCommand) -> SodaMusicActionResult {
        let response = query(action: command.rawValue)
        if let error = response.error { return .failure(error) }
        guard response.confirmed == true, let snapshot = response.snapshot else {
            return .failure("播放器尚未确认操作结果，请重试")
        }
        return .success(snapshot)
    }

    func launch() -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let launched = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in launched.signal() }
        guard launched.wait(timeout: .now() + 4) == .success else { return false }
        return isRunning
    }

    func prepareSession() -> String? {
        if read().snapshot != nil { return nil }
        guard AXIsProcessTrusted() else {
            SodaSessionStarter.requestPermission()
            return "首次启动汽水音乐播放需要辅助功能权限，请授权后重试。"
        }
        let deadline = Date().addingTimeInterval(7)
        var didPress = false
        repeat {
            if read().snapshot != nil { return nil }
            if !didPress { didPress = SodaSessionStarter.pressPlay() }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return "汽水音乐尚未提供可播放的歌曲，请检查登录、网络或歌曲播放权限。"
    }

    private func query(action: String) -> SodaMusicResponse {
        guard let scriptURL else { return SodaMusicResponse(error: "播放器组件缺失，请重新安装灵动岛") }
        let result = CommandRunner.run(
            executable: "/usr/bin/osascript",
            arguments: ["-l", "JavaScript", scriptURL.path, action, bundleIdentifier],
            timeout: action == "state" ? 2 : 3
        )
        guard result.succeeded else {
            return SodaMusicResponse(error: result.error.isEmpty ? "读取播放器失败，请重试" : result.error)
        }
        return SodaMusicResponse.decode(result.data) ?? SodaMusicResponse(error: "播放器返回了无法识别的信息")
    }
}
