import AppKit
import ApplicationServices
import Combine
import Darwin
import Foundation
import ImageIO

enum MediaPlaybackState: Equatable { case playing, paused, stopped, unavailable }

enum MediaArtworkSource: Hashable {
    case url(URL)
    case embedded(Data)
}

struct MediaTrack: Equatable {
    let title: String
    let artist: String
    /// AppleScript 播放器返回封面地址，系统 Now Playing 播放器直接返回图片数据。
    var artwork: MediaArtworkSource?
    var album: String = ""
}

enum MediaPlayerOption: String, CaseIterable, Identifiable {
    case spotify = "com.spotify.client"
    case music = "com.apple.Music"
    case soda = "com.soda.music"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spotify: return "Spotify"
        case .music: return "音乐"
        case .soda: return "汽水音乐"
        }
    }

    var appleScriptApplicationName: String? {
        switch self {
        case .spotify: return "Spotify"
        case .music: return "Music"
        case .soda: return nil
        }
    }

    var applicationURL: URL? {
        let fallbackPath: String
        switch self {
        case .spotify: fallbackPath = "/Applications/Spotify.app"
        case .music: fallbackPath = "/System/Applications/Music.app"
        case .soda: fallbackPath = "/Applications/汽水音乐.app"
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: rawValue)
            ?? URL(fileURLWithPath: fallbackPath)
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
    @Published private(set) var elapsedTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var sampledAt = Date()
    /// 当前曲目的封面。播放器没有给出可用封面时为 nil，视图需回退到 `playerIcon`。
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
        if permissionRequired { return selectedOption == .soda ? "首次播放待授权" : "需要播放权限" }
        if lastError != nil { return "播放器暂不可用" }
        if let title = track?.title { return title }
        if !isPlayerRunning { return "\(selectedOption?.title ?? "播放器") 未打开" }
        return "尚未播放"
    }

    var playbackControlTitle: String {
        if permissionRequired, selectedOption == .soda { return "打开汽水音乐" }
        return playbackState == .playing ? "暂停" : "播放"
    }

    var playbackControlSymbol: String {
        if permissionRequired, selectedOption == .soda { return "arrow.up.forward.app" }
        return playbackState == .playing ? "pause.fill" : "play.fill"
    }

    private let backendQueue = DispatchQueue(label: "dynamic-island.media.backend", qos: .userInitiated)
    private let scriptRunner = AppleScriptRunner()
    private let sodaMusic = SodaMusicController(
        scriptURL: AppResources.url(forResource: "NowPlayingBridge", withExtension: "js")
    )
    private var pollInFlight = false
    private var lastSuccessfulPoll = Date.distantPast
    private var commandError: String?
    private var expectedPlaybackState: MediaPlaybackState?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isSleeping = false
    private var consumers = Set<String>()
    private var activationObserver: NSObjectProtocol?
    private var resumeAfterPermission = false
    private var permissionWatchTimer: DispatchSourceTimer?
    private var pollTimer: DispatchSourceTimer?
    private var settingsCancellable: AnyCancellable?
    private var observedBinding: String?
    private var generation = 0
    private var deniedPlayers = Set<String>()
    private var iconCache: [String: NSImage] = [:]
    private var loadedArtworkSource: MediaArtworkSource?
    private var artworkTask: URLSessionDataTask?
    private var artworkCache: [MediaArtworkSource: NSImage] = [:]
    private var artworkCacheOrder: [MediaArtworkSource] = []
    private static let artworkCacheLimit = 3
    private static let artworkByteLimit = 6 * 1024 * 1024
    private lazy var artworkSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    private init() {
        // Do not touch SettingsStore while the static singleton is being constructed.
        DispatchQueue.main.async { [weak self] in self?.observeSettings() }
    }
    deinit {
        pollTimer?.cancel(); artworkTask?.cancel(); permissionWatchTimer?.cancel()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
    }

    var selectedOption: MediaPlayerOption? {
        guard let id = SettingsStore.shared.mediaPlayerBundleID else { return nil }
        return MediaPlayerOption(rawValue: id)
    }

    func setActive(_ active: Bool, consumer: String) {
        let previouslyActive = !consumers.isEmpty
        if active { consumers.insert(consumer) } else { consumers.remove(consumer) }
        guard previouslyActive != !consumers.isEmpty else { return }
        startPolling()
        if active { refreshNow() }
    }

    func refreshNow() {
        refreshAccessibilityStatus()
        guard !pollInFlight, !isBusy, !isSleeping else { return }
        guard let player = selectedOption else {
            applyUnavailable(generation: generation, playerID: nil, running: false)
            return
        }
        // MediaRemote can recover a Soda session without accessibility permission.
        guard player == .soda || !deniedPlayers.contains(player.rawValue) else { return }
        let token = generation
        pollInFlight = true
        backendQueue.async { [weak self] in
            self?.poll(player: player, generation: token)
            DispatchQueue.main.async {
                guard let self else { return }
                self.pollInFlight = false
                if token != self.generation { self.refreshNow() }
            }
        }
    }
    func togglePlayPause() {
        refreshAccessibilityStatus()
        if permissionRequired, selectedOption == .soda {
            openPlayer()
            return
        }
        cancelPermissionWatch()
        execute(.playPause)
    }
    func previousTrack() { execute(.previous) }
    func nextTrack() { execute(.next) }

    func openPlayer() {
        cancelPermissionWatch()
        guard let url = selectedOption?.applicationURL else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func openPermissionSettings() {
        if selectedOption == .soda {
            SodaSessionStarter.requestPermission()
            if resumeAfterPermission { watchForPermission() }
            return
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else { return }
        NSWorkspace.shared.open(url)
    }

    func retryConnection() {
        refreshAccessibilityStatus()
        if resumeAfterPermission, selectedOption == .soda, AccessibilityPermission.shared.isGranted {
            cancelPermissionWatch()
            execute(.play)
            return
        }
        if permissionRequired, selectedOption == .soda {
            refreshNow()
            return
        }
        commandError = nil
        lastError = nil
        permissionRequired = false
        if let player = selectedOption { deniedPlayers.remove(player.rawValue) }
        refreshNow()
    }

    private func refreshAccessibilityStatus() {
        if AccessibilityPermission.shared.refresh(), selectedOption == .soda, permissionRequired {
            permissionRequired = false
            commandError = nil
            lastError = nil
            deniedPlayers.remove(MediaPlayerOption.soda.rawValue)
        }
    }

    private func watchForPermission() {
        permissionWatchTimer?.cancel()
        let deadline = Date().addingTimeInterval(120)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            guard self.selectedOption == .soda, self.resumeAfterPermission, Date() < deadline else {
                self.cancelPermissionWatch()
                return
            }
            self.resumePlaybackIfAuthorized()
        }
        permissionWatchTimer = timer
        timer.resume()
    }

    private func resumePlaybackIfAuthorized() {
        refreshAccessibilityStatus()
        guard permissionWatchTimer != nil, resumeAfterPermission,
              AccessibilityPermission.shared.isGranted, !isBusy else { return }
        cancelPermissionWatch()
        execute(.play)
    }

    private func cancelPermissionWatch() {
        permissionWatchTimer?.cancel()
        permissionWatchTimer = nil
        resumeAfterPermission = false
    }

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
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didWakeNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let self else { return }
                if name == NSWorkspace.didWakeNotification {
                    self.isSleeping = false
                    self.startPolling()
                    if !self.consumers.isEmpty { self.refreshNow() }
                    return
                }
                if let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                   application.bundleIdentifier == self.selectedOption?.rawValue, !self.consumers.isEmpty { self.refreshNow() }
            })
        }
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isSleeping = true
            self?.cancelPermissionWatch()
            self?.startPolling()
        })
        activationObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.resumePlaybackIfAuthorized()
        }
    }

    private func bindingDidChange() {
        let binding = SettingsStore.shared.mediaPlayerBundleID
        guard observedBinding != binding else { return }
        observedBinding = binding
        generation &+= 1
        lastSuccessfulPoll = .distantPast
        commandError = nil
        cancelPermissionWatch()
        expectedPlaybackState = nil
        elapsedTime = 0; duration = 0
        artworkTask?.cancel()
        track = nil; playbackState = .unavailable; lastError = nil
        permissionRequired = false; isPlayerRunning = false; isBusy = false
        artwork = nil; loadedArtworkSource = nil; avatarImage = nil; avatarTint = nil
        artworkCache.removeAll()
        artworkCacheOrder.removeAll()
        startPolling()
        guard selectedOption?.isInstalled == true else { return }
        if !consumers.isEmpty { refreshNow() }
    }

    private func startPolling() {
        pollTimer?.cancel()
        pollTimer = nil
        guard !consumers.isEmpty, !isSleeping, selectedOption != nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.25, repeating: 2, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            self?.refreshNow()
        }
        pollTimer = timer; timer.resume()
    }

    private func poll(player: MediaPlayerOption, generation token: Int) {
        guard DispatchQueue.main.sync(execute: { token == generation && player == selectedOption && !isSleeping }) else { return }
        guard isRunning(player) else {
            applyUnavailable(generation: token, playerID: player.rawValue, running: false); return
        }
        if player == .soda {
            pollSodaMusic(player, generation: token)
            return
        }
        guard let script = player.script(for: .state) else {
            applyError("无法创建播放器脚本", permissionRequired: false, generation: token, playerID: player.rawValue)
            return
        }
        let result = scriptRunner.execute(script, timeout: 4)
        guard result.success else {
            applyError(result.error ?? "读取播放器状态失败", permissionRequired: result.isPermissionError, generation: token, playerID: player.rawValue); return
        }
        let title = result.values[safe: 0]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let artist = result.values[safe: 1]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let state = Self.playbackState(from: result.values[safe: 2]?.lowercased() ?? "")
        let artwork = Self.artworkURL(from: result.values[safe: 3] ?? "").map(MediaArtworkSource.url)
        let newTrack = title.isEmpty || title == "missing value"
            ? nil
            : MediaTrack(title: title, artist: artist.isEmpty ? player.title : artist, artwork: artwork)
        applyTiming(elapsed: Double(result.values[safe: 4] ?? "") ?? 0, duration: Double(result.values[safe: 5] ?? "") ?? 0, generation: token)
        applyState(track: newTrack, playbackState: state, running: true, error: nil, generation: token, playerID: player.rawValue)
    }

    private func pollSodaMusic(_ player: MediaPlayerOption, generation token: Int) {
        let response = sodaMusic.read()
        guard let snapshot = response.snapshot else {
            if let error = response.error { applyReadFailure(error, player: player, generation: token) }
            else { applyUnavailable(generation: token, playerID: player.rawValue, running: true) }
            return
        }
        applySodaSnapshot(snapshot, player: player, generation: token)
    }

    private func applySodaSnapshot(_ snapshot: SodaMusicSnapshot, player: MediaPlayerOption, generation token: Int) {
        let image = snapshot.artworkBase64.flatMap { Data(base64Encoded: $0) }.flatMap {
            $0.count <= Self.artworkByteLimit ? MediaArtworkSource.embedded($0) : nil
        }
        let newTrack = MediaTrack(
            title: snapshot.title,
            artist: snapshot.artist.isEmpty ? player.title : snapshot.artist,
            artwork: image,
            album: snapshot.album
        )
        applyTiming(elapsed: snapshot.progress, duration: snapshot.duration, generation: token)
        let state: MediaPlaybackState = snapshot.isPlaying ? .playing : .paused
        applyState(track: newTrack, playbackState: state, running: true, error: nil, generation: token, playerID: player.rawValue)
    }

    private func execute(_ command: MediaCommand) {
        ensureBinding()
        bindingDidChange()
        guard let player = selectedOption, player.isInstalled, !isBusy else { return }
        deniedPlayers.remove(player.rawValue)
        commandError = nil
        switch command {
        case .play: expectedPlaybackState = .playing
        case .playPause: expectedPlaybackState = playbackState == .playing ? .paused : .playing
        default: expectedPlaybackState = nil
        }
        permissionRequired = false
        isBusy = true; lastError = nil
        let token = generation
        let intendedState = expectedPlaybackState
        backendQueue.async { [weak self] in
            guard let self else { return }
            guard DispatchQueue.main.sync(execute: { token == self.generation && player == self.selectedOption }) else { return }
            if player == .soda {
                self.executeSodaMusic(command, intendedState: intendedState, player: player, generation: token)
                return
            }
            // 不预检 Apple Events 权限：AEDeterminePermissionToAutomateTarget 在拿不到
            // TCC 响应时会无限期阻塞（实测卡死整条后台队列，播放控制全废）。
            // 直接发脚本，让系统走原生授权弹窗；真被拒了脚本会带着权限错误回来。
            if self.isRunning(player) {
                guard let script = player.script(for: command) else {
                    self.finishCommand(ScriptResult(success: false, values: [], error: "无法创建播放器脚本"), player: player, generation: token)
                    return
                }
                let result = self.scriptRunner.execute(script, timeout: 2)
                self.finishCommand(result, player: player, generation: token); return
            }
            guard command == .playPause || command == .play else {
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
            guard let playScript = player.script(for: .play) else {
                self.finishCommand(ScriptResult(success: false, values: [], error: "无法创建播放器脚本"), player: player, generation: token)
                return
            }
            let startResult = self.scriptRunner.execute(playScript, timeout: 2)
            self.finishCommand(startResult, player: player, generation: token)
        }
    }

    private func executeSodaMusic(_ command: MediaCommand, intendedState: MediaPlaybackState?, player: MediaPlayerOption, generation token: Int) {
        let wasRunning = sodaMusic.isRunning
        if !wasRunning {
            guard command == .playPause || command == .play else {
                finishCommand(ScriptResult(success: false, values: [], error: "播放器尚未运行"), player: player, generation: token)
                return
            }
            guard sodaMusic.launch() else {
                finishCommand(ScriptResult(success: false, values: [], error: "\(player.title)启动超时"), player: player, generation: token)
                return
            }
        }

        let hasSession = sodaMusic.read().snapshot != nil
        if !hasSession, command == .play || command == .playPause {
            if let error = sodaMusic.prepareSession() {
                finishCommand(ScriptResult(success: false, values: [], error: error), player: player, generation: token)
                return
            }
        }

        let sodaCommand: SodaMusicCommand
        switch command {
        case .play:
            sodaCommand = .play
        case .playPause:
            // Preserve the displayed button's intent even if metadata arrives late.
            sodaCommand = intendedState == .paused && hasSession ? .pause : .play
        case .previous:
            sodaCommand = .previous
        case .next:
            sodaCommand = .next
        case .state:
            pollSodaMusic(player, generation: token)
            return
        }

        switch sodaMusic.send(sodaCommand) {
        case .success(let snapshot):
            applySodaSnapshot(snapshot, player: player, generation: token)
            backendCommandFinished(error: nil, permissionRequired: false, generation: token)
        case .failure(let error):
            finishCommand(ScriptResult(success: false, values: [], error: error), player: player, generation: token)
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
            guard let self, token == self.generation, player.rawValue == self.selectedOption?.rawValue else { return }
            if result.success {
                self.deniedPlayers.remove(player.rawValue)
            } else if result.isPermissionError, player != .soda {
                self.deniedPlayers.insert(player.rawValue)
            }
        }
        backendCommandFinished(error: result.success ? nil : result.error, permissionRequired: result.isPermissionError, generation: token)
        if result.success { poll(player: player, generation: token) }
    }
    private func backendCommandFinished(error: String?, permissionRequired required: Bool, generation token: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, token == self.generation else { return }
            self.commandError = error
            self.resumeAfterPermission = required && self.selectedOption == .soda
            self.isBusy = false; self.permissionRequired = required; self.setLastError(error)
        }
    }

    private func applyUnavailable(generation token: Int, playerID: String?, running: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, token == self.generation, playerID == self.selectedOption?.rawValue || playerID == nil else { return }
            self.elapsedTime = 0; self.duration = 0
            self.applyIfChanged(track: nil, playbackState: .unavailable, running: running, error: nil)
        }
    }
    private func applyTiming(elapsed: TimeInterval, duration: TimeInterval, generation token: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, token == self.generation else { return }
            self.elapsedTime = elapsed.isFinite ? max(0, elapsed) : 0
            self.duration = duration.isFinite ? max(0, duration) : 0
            self.sampledAt = Date()
        }
    }
    private func applyReadFailure(_ error: String, player: MediaPlayerOption, generation token: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, token == self.generation, player.rawValue == self.selectedOption?.rawValue else { return }
            if Date().timeIntervalSince(self.lastSuccessfulPoll) < 6, self.track != nil { return }
            self.applyIfChanged(track: nil, playbackState: .unavailable, running: true, error: error)
        }
    }
    private func applyError(_ error: String, permissionRequired required: Bool, generation token: Int, playerID: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, token == self.generation, playerID == self.selectedOption?.rawValue else { return }
            self.permissionRequired = required
            if required { self.deniedPlayers.insert(playerID) }
            self.applyIfChanged(track: nil, playbackState: .unavailable, running: true, error: error)
        }
    }
    private func applyState(track newTrack: MediaTrack?, playbackState state: MediaPlaybackState, running: Bool, error: String?, generation token: Int, playerID: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, token == self.generation, playerID == self.selectedOption?.rawValue else { return }
            self.lastSuccessfulPoll = Date()
            if self.expectedPlaybackState == state || (self.permissionRequired && self.selectedOption == .soda) {
                self.commandError = nil
                self.expectedPlaybackState = nil
                self.cancelPermissionWatch()
            }
            if self.commandError == nil { self.permissionRequired = false }
            self.applyIfChanged(track: newTrack, playbackState: state, running: running, error: error)
        }
    }
    private func applyIfChanged(track newTrack: MediaTrack?, playbackState state: MediaPlaybackState, running: Bool, error: String?) {
        if track != newTrack { track = newTrack }
        loadArtwork(for: newTrack?.artwork)
        refreshAvatar()
        if playbackState != state { playbackState = state }
        if isPlayerRunning != running { isPlayerRunning = running }; setLastError(error ?? commandError)
    }

    /// 头像与波纹取色共用同一张图：本地封面 > 播放器图标。
    private func refreshAvatar() {
        let image = artwork ?? playerIcon
        if avatarImage === image { return }
        avatarImage = image
        avatarTint = image.flatMap { ArtworkTint.color(from: $0) }
    }

    /// 只在封面来源变化时取图：本地文件读盘，图片链接走网络，系统 Now Playing 直接解码内嵌数据。
    /// 结果按来源缓存，播放器轮询刷新歌名不会重复解码或重复请求。
    private func loadArtwork(for source: MediaArtworkSource?) {
        guard source != loadedArtworkSource else { return }
        loadedArtworkSource = source
        artworkTask?.cancel()
        artworkTask = nil
        guard let source else {
            artwork = nil
            refreshAvatar()
            return
        }
        if let cached = artworkCache[source] {
            artwork = cached
            refreshAvatar()
            return
        }
        artwork = nil
        refreshAvatar()
        let token = generation
        switch source {
        case .url(let url):
            if url.isFileURL {
                backendQueue.async { [weak self] in
                    let image = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap(Self.thumbnail)
                    self?.deliverArtwork(image, for: source, token: token)
                }
                return
            }
            let task = artworkSession.dataTask(with: url) { [weak self] data, _, _ in
                guard let self, let data, data.count <= Self.artworkByteLimit else { return }
                self.deliverArtwork(Self.thumbnail(data: data), for: source, token: token)
            }
            artworkTask = task
            task.resume()
        case .embedded(let data):
            backendQueue.async { [weak self] in
                self?.deliverArtwork(Self.thumbnail(data: data), for: source, token: token)
            }
        }
    }

    private static func thumbnail(data: Data) -> NSImage? {
        CGImageSourceCreateWithData(data as CFData, nil).flatMap(thumbnail)
    }

    private static func thumbnail(_ source: CGImageSource) -> NSImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 256,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    private func deliverArtwork(_ image: NSImage?, for source: MediaArtworkSource, token: Int) {
        guard let image, image.size != .zero else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, token == self.generation, self.loadedArtworkSource == source else { return }
            self.rememberArtwork(image, for: source)
            self.artwork = image
            self.refreshAvatar()
        }
    }

    private func rememberArtwork(_ image: NSImage, for source: MediaArtworkSource) {
        artworkCache[source] = image
        artworkCacheOrder.removeAll { $0 == source }
        artworkCacheOrder.append(source)
        while artworkCacheOrder.count > Self.artworkCacheLimit {
            artworkCache.removeValue(forKey: artworkCacheOrder.removeFirst())
        }
    }
    private func setLastError(_ error: String?) { if lastError != error { lastError = error } }
    private func isRunning(_ player: MediaPlayerOption) -> Bool { NSRunningApplication.runningApplications(withBundleIdentifier: player.rawValue).contains { !$0.isTerminated } }
    private func permissionMessage(for player: MediaPlayerOption) -> String { "请在系统设置 > 隐私与安全性 > 自动化中允许本应用控制\(player.title)" }
    private static func playbackState(from value: String) -> MediaPlaybackState {
        switch value {
        case "playing", "播放中", "正在播放": return .playing
        case "paused", "已暂停", "暂停": return .paused
        case "stopped", "已停止", "停止": return .stopped
        default: return .unavailable
        }
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
        return value.contains("not authorized") || value.contains("not permitted") || value.contains("权限") || value.contains("-1743")
    }
}

private final class AppleScriptRunner {
    func execute(_ source: String, timeout: TimeInterval) -> ScriptResult {
        let output = CommandRunner.run(executable: "/usr/bin/osascript", arguments: ["-e", source], timeout: timeout)
        let text = String(decoding: output.data, as: UTF8.self).trimmingCharacters(in: .newlines)
        return ScriptResult(success: output.succeeded,
                            values: text.components(separatedBy: String(UnicodeScalar(31))),
                            error: output.succeeded ? nil : output.error)
    }
}

private extension MediaPlayerOption {
    func script(for command: MediaCommand) -> String? {
        guard let app = appleScriptApplicationName else { return nil }
        switch command {
        case .state: return """
            tell application "\(app)"
                set currentTitle to ""
                set currentArtist to ""
                set currentArtwork to ""
                set currentPosition to "0"
                set currentDuration to "0"
                try
                    set currentTitle to name of current track
                    set currentArtist to artist of current track
                end try
                try
                    set currentArtwork to (artwork url of current track) as text
                end try
                try
                    set currentPosition to (player position as text)
                    set currentDuration to (duration of current track)
                    if "\(app)" is "Spotify" then set currentDuration to currentDuration / 1000
                    set currentDuration to currentDuration as text
                end try
                set separator to ASCII character 31
                return currentTitle & separator & currentArtist & separator & (player state as text) & separator & currentArtwork & separator & currentPosition & separator & currentDuration
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
