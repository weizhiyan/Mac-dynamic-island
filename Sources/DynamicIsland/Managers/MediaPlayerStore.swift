import AppKit
import ApplicationServices
import Combine
import Foundation

enum MediaPlaybackState: Equatable { case playing, paused, stopped, unavailable }

struct MediaTrack: Equatable {
    let title: String
    let artist: String
    /// 播放器给出的封面地址：本地文件，或播放器自己暴露的图片链接。
    var artworkURL: URL?
}

enum MediaPlayerOption: String, CaseIterable, Identifiable {
    case spotify = "com.spotify.client"
    case music = "com.apple.Music"
    var id: String { rawValue }
    var title: String { self == .spotify ? "Spotify" : "音乐" }
    var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue)
            ?? URL(fileURLWithPath: self == .spotify ? "/Applications/Spotify.app" : "/System/Applications/Music.app")
    }
    var isInstalled: Bool {
        guard let url = applicationURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}

final class MediaPlayerStore: ObservableObject {
    static let shared = MediaPlayerStore()

    @Published private(set) var track: MediaTrack?
    @Published private(set) var playbackState: MediaPlaybackState = .unavailable
    @Published private(set) var lastError: String?
    @Published private(set) var isBusy = false
    @Published private(set) var permissionRequired = false
    @Published private(set) var isPlayerRunning = false
    /// 当前曲目的本地封面。播放器没有给出可用本地封面时为 nil，视图需回退到 `playerIcon`。
    @Published private(set) var artwork: NSImage?
    /// 紧凑带与展开摘要实际展示的头像：本地封面 > 播放器图标。
    @Published private(set) var avatarImage: NSImage?
    /// 从头像提取的主色，供波纹着色；头像接近黑白时返回 nil，由波纹回退成白色。
    @Published private(set) var avatarTint: NSColor?
    var isCardVisible: Bool { selectedOption?.isInstalled == true }

    /// 收起态是否需要展示音乐内容层：有曲目，且播放器在播放或暂停。
    /// 停止、无曲目、未绑定都不展示，刘海回到基础宽度。
    var hasCompactMedia: Bool {
        guard track != nil else { return false }
        return playbackState == .playing || playbackState == .paused
    }

    /// 播放器应用图标，作为封面缺失时的回退。
    var playerIcon: NSImage? {
        guard let option = selectedOption, let url = option.applicationURL else { return nil }
        let path = url.path
        if let cached = iconCache[path] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        iconCache[path] = icon
        return icon.size == .zero ? nil : icon
    }

    /// 主状态文案：错误 > 歌名 > 未打开 > 未播放。
    var primaryStatusText: String {
        if lastError != nil { return "播放器暂不可用" }
        if let title = track?.title { return title }
        if !isPlayerRunning { return "\(selectedOption?.title ?? "播放器") 未打开" }
        return "尚未播放"
    }

    private let backendQueue = DispatchQueue(label: "dynamic-island.media.backend", qos: .utility)
    private let scriptRunner = AppleScriptRunner()
    private var pollTimer: DispatchSourceTimer?
    private var settingsCancellable: AnyCancellable?
    private var generation = 0
    private var deniedPlayers = Set<String>()
    private var iconCache: [String: NSImage] = [:]
    private var loadedArtworkURL: URL?
    private var artworkTask: URLSessionDataTask?
    private var artworkCache: [URL: NSImage] = [:]
    private var artworkCacheOrder: [URL] = []
    private static let artworkCacheLimit = 8
    private static let artworkByteLimit = 6 * 1024 * 1024
    private lazy var artworkSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 0)
        return URLSession(configuration: configuration)
    }()

    private init() {
        // Do not touch SettingsStore while the static singleton is being constructed.
        DispatchQueue.main.async { [weak self] in self?.observeSettings() }
    }
    deinit { pollTimer?.cancel(); artworkTask?.cancel() }

    var selectedOption: MediaPlayerOption? {
        guard let id = SettingsStore.shared.mediaPlayerBundleID else { return nil }
        return MediaPlayerOption(rawValue: id)
    }

    func refreshNow() {
        guard let player = selectedOption else {
            applyUnavailable(generation: generation, playerID: nil, running: false)
            return
        }
        let token = generation
        backendQueue.async { [weak self] in self?.poll(player: player, generation: token) }
    }
    func togglePlayPause() { execute(.playPause) }
    func previousTrack() { execute(.previous) }
    func nextTrack() { execute(.next) }

    /// 没绑定播放器（或绑定的应用被卸载）时，点播放/上一首/下一首家都打不开。
    /// 这里兜底：自动绑一个已安装的播放器（音乐 App 一定在），
    /// 绑定会写进设置，用户之后想换随时能在设置里改。
    private func ensureBinding() {
        let settings = SettingsStore.shared
        if let id = settings.mediaPlayerBundleID,
           MediaPlayerOption(rawValue: id)?.isInstalled == true { return }
        guard let fallback = MediaPlayerOption.allCases.first(where: { $0.isInstalled }) else { return }
        settings.mediaPlayerBundleID = fallback.rawValue
        print("🎵 未绑定播放器，自动绑定 \(fallback.title)")
    }

    private func observeSettings() {
        settingsCancellable = SettingsStore.shared.$mediaPlayerBundleID
            .removeDuplicates().receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.bindingDidChange() }
        startPolling()
        bindingDidChange()
    }

    private func bindingDidChange() {
        generation &+= 1
        track = nil; playbackState = .unavailable; lastError = nil
        permissionRequired = false; isPlayerRunning = false; isBusy = false
        artwork = nil; loadedArtworkURL = nil; avatarImage = nil; avatarTint = nil
        guard let player = selectedOption, player.isInstalled else { return }
        let token = generation
        backendQueue.async { [weak self] in self?.poll(player: player, generation: token) }
    }

    private func startPolling() {
        pollTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: backendQueue)
        timer.schedule(deadline: .now() + 0.25, repeating: 1.5, leeway: .milliseconds(150))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard let player = self.selectedOption, player.isInstalled else {
                self.applyUnavailable(generation: self.generation, playerID: nil, running: false); return
            }
            self.poll(player: player, generation: self.generation)
        }
        pollTimer = timer; timer.resume()
    }

    private func poll(player: MediaPlayerOption, generation token: Int) {
        guard isRunning(player) else {
            applyUnavailable(generation: token, playerID: player.rawValue, running: false); return
        }
        let result = scriptRunner.execute(player.script(for: .state), timeout: 4)
        guard result.success else {
            applyError(result.error ?? "读取播放器状态失败", permissionRequired: result.isPermissionError, generation: token, playerID: player.rawValue); return
        }
        let title = result.values[safe: 0]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artist = result.values[safe: 1]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let state = Self.playbackState(from: result.values[safe: 2]?.lowercased() ?? "")
        let artwork = Self.artworkURL(from: result.values[safe: 3] ?? "")
        let newTrack = title.isEmpty || title == "missing value"
            ? nil
            : MediaTrack(title: title, artist: artist.isEmpty ? player.title : artist, artworkURL: artwork)
        applyState(track: newTrack, playbackState: state, running: true, error: nil, generation: token, playerID: player.rawValue)
    }

    private func execute(_ command: MediaCommand) {
        ensureBinding()
        guard let player = selectedOption, player.isInstalled, !isBusy else { return }
        guard !deniedPlayers.contains(player.rawValue) else {
            permissionRequired = true; lastError = permissionMessage(for: player); return
        }
        isBusy = true; lastError = nil
        let token = generation
        backendQueue.async { [weak self] in
            guard let self else { return }
            // 不预检 Apple Events 权限：AEDeterminePermissionToAutomateTarget 在拿不到
            // TCC 响应时会无限期阻塞（实测卡死整条后台队列，播放控制全废）。
            // 直接发脚本，让系统走原生授权弹窗；真被拒了脚本会带着权限错误回来。
            if self.isRunning(player) {
                let result = self.scriptRunner.execute(player.script(for: command), timeout: 2)
                self.finishCommand(result, player: player, generation: token); return
            }
            guard command == .playPause else {
                self.finishCommand(ScriptResult(success: false, values: [], error: "播放器尚未运行"), player: player, generation: token)
                return
            }
            guard let url = player.applicationURL else {
                self.finishCommand(ScriptResult(success: false, values: [], error: "找不到\(player.title)应用"), player: player, generation: token); return
            }
            guard self.openApplication(url), self.waitUntilRunning(player, attempts: 6, interval: 0.5) else {
                self.finishCommand(ScriptResult(success: false, values: [], error: "\(player.title)启动超时"), player: player, generation: token); return
            }
            // Launching can restore a paused session, so always issue explicit play.
            let startResult = self.scriptRunner.execute(player.script(for: .play), timeout: 2)
            self.finishCommand(startResult, player: player, generation: token)
        }
    }

    private func openApplication(_ url: URL) -> Bool {
        let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = true
        var succeeded = false
        let semaphore = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in succeeded = error == nil; semaphore.signal() }
        _ = semaphore.wait(timeout: .now() + 3)
        return succeeded
    }
    private func waitUntilRunning(_ player: MediaPlayerOption, attempts: Int, interval: TimeInterval) -> Bool {
        for _ in 0..<attempts { if isRunning(player) { return true }; Thread.sleep(forTimeInterval: interval) }
        return isRunning(player)
    }
    private func finishCommand(_ result: ScriptResult, player: MediaPlayerOption, generation token: Int) {
        DispatchQueue.main.async { [weak self] in
            if result.success {
                self?.deniedPlayers.remove(player.rawValue)
            } else if result.isPermissionError {
                self?.deniedPlayers.insert(player.rawValue)
            }
        }
        backendCommandFinished(error: result.success ? nil : result.error, permissionRequired: result.isPermissionError, generation: token)
        if result.success { poll(player: player, generation: token) }
    }
    private func backendCommandFinished(error: String?, permissionRequired required: Bool, generation token: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, token == self.generation else { return }
            self.isBusy = false; self.permissionRequired = required; self.setLastError(error)
        }
    }

    private func applyUnavailable(generation token: Int, playerID: String?, running: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, token == self.generation, playerID == self.selectedOption?.rawValue || playerID == nil else { return }
            self.applyIfChanged(track: nil, playbackState: .unavailable, running: running, error: nil)
        }
    }
    private func applyError(_ error: String, permissionRequired required: Bool, generation token: Int, playerID: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, token == self.generation, playerID == self.selectedOption?.rawValue else { return }
            self.permissionRequired = required
            self.applyIfChanged(track: nil, playbackState: .unavailable, running: self.isPlayerRunning, error: error)
        }
    }
    private func applyState(track newTrack: MediaTrack?, playbackState state: MediaPlaybackState, running: Bool, error: String?, generation token: Int, playerID: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, token == self.generation, playerID == self.selectedOption?.rawValue else { return }
            self.applyIfChanged(track: newTrack, playbackState: state, running: running, error: error)
        }
    }
    private func applyIfChanged(track newTrack: MediaTrack?, playbackState state: MediaPlaybackState, running: Bool, error: String?) {
        if track != newTrack { track = newTrack }
        loadArtwork(for: newTrack?.artworkURL)
        refreshAvatar()
        if playbackState != state { playbackState = state }
        if isPlayerRunning != running { isPlayerRunning = running }; setLastError(error)
    }

    /// 头像与波纹取色共用同一张图：本地封面 > 播放器图标。
    private func refreshAvatar() {
        let image = artwork ?? playerIcon
        if avatarImage === image { return }
        avatarImage = image
        avatarTint = image.flatMap { ArtworkTint.color(from: $0) }
    }

    /// 只在封面地址变化时取图：本地文件读盘，播放器给出的图片链接走网络；
    /// 结果按地址缓存，播放器轮询刷新歌名不会重复解码或重复请求。
    private func loadArtwork(for url: URL?) {
        guard url != loadedArtworkURL else { return }
        loadedArtworkURL = url
        artworkTask?.cancel()
        artworkTask = nil
        guard let url else {
            artwork = nil
            refreshAvatar()
            return
        }
        if let cached = artworkCache[url] {
            artwork = cached
            refreshAvatar()
            return
        }
        artwork = nil
        refreshAvatar()
        let token = generation
        if url.isFileURL {
            backendQueue.async { [weak self] in self?.deliverArtwork(NSImage(contentsOf: url), for: url, token: token) }
            return
        }
        let task = artworkSession.dataTask(with: url) { [weak self] data, _, _ in
            guard let self, let data, data.count <= Self.artworkByteLimit else { return }
            self.deliverArtwork(NSImage(data: data), for: url, token: token)
        }
        artworkTask = task
        task.resume()
    }

    private func deliverArtwork(_ image: NSImage?, for url: URL, token: Int) {
        guard let image, image.size != .zero else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, token == self.generation, self.loadedArtworkURL == url else { return }
            self.rememberArtwork(image, for: url)
            self.artwork = image
            self.refreshAvatar()
        }
    }

    private func rememberArtwork(_ image: NSImage, for url: URL) {
        artworkCache[url] = image
        artworkCacheOrder.removeAll { $0 == url }
        artworkCacheOrder.append(url)
        while artworkCacheOrder.count > Self.artworkCacheLimit {
            artworkCache.removeValue(forKey: artworkCacheOrder.removeFirst())
        }
    }
    private func setLastError(_ error: String?) { if lastError != error { lastError = error } }
    private func isRunning(_ player: MediaPlayerOption) -> Bool { NSRunningApplication.runningApplications(withBundleIdentifier: player.rawValue).contains { !$0.isTerminated } }
    private func permissionMessage(for player: MediaPlayerOption) -> String { "请在系统设置 > 隐私与安全性 > 自动化中允许本应用控制\(player.title)" }
    private static func playbackState(from value: String) -> MediaPlaybackState {
        switch value { case "playing": return .playing; case "paused": return .paused; case "stopped": return .stopped; default: return .unavailable }
    }
    /// 播放器给出的封面地址：本地文件必须存在，网络地址只接受 http/https 且带主机名，其余一律忽略。
    private static func artworkURL(from value: String) -> URL? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != "missing value" else { return nil }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return nil }
        switch scheme {
        case "file": return FileManager.default.fileExists(atPath: url.path) ? url : nil
        case "http", "https": return url.host?.isEmpty == false ? url : nil
        default: return nil
        }
    }
}

private enum MediaCommand: Equatable { case state, play, playPause, previous, next }
private struct ScriptResult {
    let success: Bool; let values: [String]; let error: String?
    var isPermissionError: Bool {
        guard let error else { return false }; let value = error.lowercased()
        return value.contains("not authorized") || value.contains("not permitted") || value.contains("权限")
    }
}

private final class AppleScriptRunner {
    private let queue = DispatchQueue(label: "dynamic-island.media.apple-script")
    private let lock = NSLock(); private var busy = false
    func execute(_ source: String, timeout: TimeInterval) -> ScriptResult {
        lock.lock(); guard !busy else { lock.unlock(); return ScriptResult(success: false, values: [], error: "播放器操作仍在进行") }; busy = true; lock.unlock()
        let semaphore = DispatchSemaphore(value: 0); var result = ScriptResult(success: false, values: [], error: "播放器操作超时")
        queue.async { [weak self] in
            result = Self.run(source); self?.lock.lock(); self?.busy = false; self?.lock.unlock(); semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + timeout) == .timedOut { return ScriptResult(success: false, values: [], error: "播放器操作超时") }
        return result
    }
    private static func run(_ source: String) -> ScriptResult {
        var error: NSDictionary?; guard let script = NSAppleScript(source: source) else { return ScriptResult(success: false, values: [], error: "无法创建播放器脚本") }
        let descriptor = script.executeAndReturnError(&error)
        if let error { return ScriptResult(success: false, values: [], error: error[NSAppleScript.errorMessage] as? String ?? "播放器自动化失败") }
        if descriptor.numberOfItems > 0 { return ScriptResult(success: true, values: (1...descriptor.numberOfItems).compactMap { descriptor.atIndex($0)?.stringValue }, error: nil) }
        return ScriptResult(success: true, values: descriptor.stringValue.map { [$0] } ?? [], error: nil)
    }
}

private extension MediaPlayerOption {
    func script(for command: MediaCommand) -> String {
        let app = self == .spotify ? "Spotify" : "Music"
        switch command {
        case .state: return """
            tell application "\(app)"
                set currentTitle to ""
                set currentArtist to ""
                set currentArtwork to ""
                try
                    set currentTitle to name of current track
                    set currentArtist to artist of current track
                end try
                try
                    set currentArtwork to (artwork url of current track) as text
                end try
                return {currentTitle, currentArtist, (player state as text), currentArtwork}
            end tell
            """
        case .play: return "tell application \"\(app)\" to play"
        case .playPause: return "tell application \"\(app)\" to playpause"
        case .previous: return "tell application \"\(app)\" to previous track"
        case .next: return "tell application \"\(app)\" to next track"
        }
    }
}
private extension Array { subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil } }

final class SystemMetricsStore: ObservableObject {
    static let shared = SystemMetricsStore()
    @Published private(set) var cpuUsage: Double = 0
    @Published private(set) var memoryUsage: Double = 0
    private let queue = DispatchQueue(label: "dynamic-island.metrics", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var hostPort: mach_port_t = mach_host_self()
    private var previousTicks: (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)?
    private init() {}
    deinit { timer?.cancel(); mach_port_deallocate(mach_task_self_, hostPort) }
    func setActive(_ active: Bool) {
        queue.async { [weak self] in
            guard let self else { return }; self.timer?.cancel(); self.timer = nil
            guard active else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue); timer.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(100)); timer.setEventHandler { [weak self] in self?.refresh() }; self.timer = timer; timer.resume()
        }
    }
    private func refresh() {
        let cpu = readCPUUsage(); let memory = readMemoryUsage()
        DispatchQueue.main.async { [weak self] in guard let self else { return }; if self.cpuUsage != cpu { self.cpuUsage = cpu }; if self.memoryUsage != memory { self.memoryUsage = memory } }
    }
    private func readCPUUsage() -> Double {
        var info = host_cpu_load_info(); var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count) } }
        guard result == KERN_SUCCESS else { return cpuUsage }
        let ticks = (user: info.cpu_ticks.0, system: info.cpu_ticks.1, idle: info.cpu_ticks.2, nice: info.cpu_ticks.3); defer { previousTicks = ticks }; guard let previousTicks else { return 0 }
        let user = Double(ticks.user &- previousTicks.user), system = Double(ticks.system &- previousTicks.system), idle = Double(ticks.idle &- previousTicks.idle), nice = Double(ticks.nice &- previousTicks.nice); let total = user + system + idle + nice
        return total > 0 ? min(max((total - idle) / total, 0), 1) : 0
    }
    private func readMemoryUsage() -> Double {
        var stats = vm_statistics64(); var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(hostPort, HOST_VM_INFO64, $0, &count) } }; guard result == KERN_SUCCESS else { return memoryUsage }
        var pageSize: vm_size_t = 0; host_page_size(hostPort, &pageSize)
        let activePages = UInt64(stats.active_count)
        let purgeablePages = UInt64(stats.purgeable_count)
        let reclaimableActive = min(activePages, purgeablePages)
        let usedPages = (activePages - reclaimableActive) + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return min(max(Double(usedPages) * Double(pageSize) / Double(ProcessInfo.processInfo.physicalMemory), 0), 1)
    }
}
