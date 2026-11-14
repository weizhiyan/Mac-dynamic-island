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
    var accepted: Bool?

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
    private let queryOverride: ((String) -> SodaMusicResponse)?
    private let isTrusted: () -> Bool
    private let startSession: () -> Bool

    init(scriptURL: URL?, queryOverride: ((String) -> SodaMusicResponse)? = nil,
         isTrusted: @escaping () -> Bool = { AXIsProcessTrusted() },
         startSession: @escaping () -> Bool = { SodaSessionStarter.pressPlay() }) {
        self.scriptURL = scriptURL
        self.queryOverride = queryOverride
        self.isTrusted = isTrusted
        self.startSession = startSession
    }

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
        configuration.activates = false
        let launched = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in launched.signal() }
        guard launched.wait(timeout: .now() + 4) == .success else { return false }
        return isRunning
    }

    func prepareSession() -> String? {
        if read().snapshot != nil { return nil }
        // A player can retain its media command handler before publishing track metadata.
        let resumed = query(action: "resume")
        if resumed.confirmed == true, resumed.snapshot?.isPlaying == true { return nil }
        if resumed.accepted == true { return "已请求汽水音乐播放，正在等待歌曲信息。" }
        guard isTrusted() else {
            return "当前版本的辅助功能权限尚未生效。可前往授权后继续播放，或先在汽水音乐中播放一首歌曲。"
        }
        let deadline = Date().addingTimeInterval(5)
        var didPress = false
        repeat {
            if read().snapshot != nil { return nil }
            if !didPress { didPress = startSession() }
            Thread.sleep(forTimeInterval: 0.25)
        } while Date() < deadline
        return didPress
            ? "已请求汽水音乐播放，但尚未收到歌曲信息。请检查播放器登录、网络或歌曲是否可播放。"
            : "未找到汽水音乐的播放按钮。请先在播放器中选择一首歌曲，之后可在灵动岛直接播放或暂停。"
    }

    private func query(action: String) -> SodaMusicResponse {
        if let queryOverride { return queryOverride(action) }
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
