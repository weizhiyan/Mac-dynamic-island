import AppKit
import Foundation

@main
struct PlaybackMetricsChecks {
    static var failures = 0

    static func expect(_ label: String, _ condition: Bool) {
        print("\(condition ? "✓" : "✗") \(label)")
        if !condition { failures += 1 }
    }

    static func main() {
        let cpu = CPUBreakdown.between([100, 100, 100, 0], [125, 115, 160, 0])
        expect("CPU 按采样差值计算用户、系统和空闲", cpu?.usage == 0.4 && cpu?.idle == 0.6)
        let wrapped = CPUBreakdown.between([UInt32.max - 4, 0, 0, 0], [5, 5, 5, 0])
        expect("CPU 计数器回绕不产生溢出", wrapped?.usage == 0.75)
        expect("CPU 无有效样本时不伪造 0%", CPUBreakdown.between([0, 0, 0, 0], [0, 0, 0, 0]) == nil)
        let memory = MemoryBreakdown.make(total: 1000, pageSize: 1, internalPages: 500, purgeablePages: 100,
                                         wiredPages: 100, compressedPages: 50, externalPages: 200, swap: 20, pressure: 1)
        expect("内存不把可清除缓存重复计为应用用量", memory.used == 550 && memory.available == 450 && memory.cached == 300)
        let clamped = MemoryBreakdown.make(total: 100, pageSize: 1, internalPages: 10, purgeablePages: 100,
                                          wiredPages: 150, compressedPages: 0, externalPages: 0, swap: 0, pressure: nil)
        expect("内存计算防止无符号下溢及超出物理内存", clamped.app == 0 && clamped.usage == 1)

        let payload = #"{"snapshot":{"title":"歌名,带逗号","artist":"歌手","album":"专辑","isPlaying":false,"progress":12,"duration":120,"bundleIdentifier":"com.soda.music","identifier":"track-1"},"confirmed":true}"#
        let response = SodaMusicResponse.decode(Data(payload.utf8))
        expect("保留歌名标点与真实暂停状态", response?.snapshot?.title == "歌名,带逗号" && response?.snapshot?.isPlaying == false)
        expect("不把其他播放器信息显示为汽水音乐", SodaMusicResponse.decode(Data(payload.replacingOccurrences(of: "com.soda.music", with: "com.other.app").utf8))?.snapshot == nil)
        expect("无歌曲返回可用空状态", SodaMusicResponse.decode(Data(#"{"snapshot":null}"#.utf8))?.snapshot == nil)
        expect("无效响应不会成为播放成功", SodaMusicResponse.decode(Data("bad payload".utf8)) == nil)

        let quick = CommandRunner.run(executable: "/usr/bin/printf", arguments: ["ok"], timeout: 1)
        expect("有界子进程保留正确输出", quick.succeeded && String(decoding: quick.data, as: UTF8.self) == "ok")
        let started = Date()
        let timeout = CommandRunner.run(executable: "/bin/sleep", arguments: ["10"], timeout: 0.15)
        expect("超时子进程停止，不阻塞后续播放", !timeout.succeeded && Date().timeIntervalSince(started) < 2)

        let store = SystemMetricsStore.shared
        store.setActive(true, consumer: "island")
        store.setActive(true, consumer: "metrics-window")
        RunLoop.main.run(until: Date().addingTimeInterval(0.45))
        let first = store.lastUpdated
        expect("系统指标能读取有效实时样本", store.cpu != nil && store.memory != nil)
        store.setActive(false, consumer: "island")
        RunLoop.main.run(until: Date().addingTimeInterval(1.15))
        expect("收起灵动岛后详情窗口继续采样", first != nil && store.lastUpdated != first)
        store.setActive(false, consumer: "metrics-window")
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let stopped = store.lastUpdated
        RunLoop.main.run(until: Date().addingTimeInterval(1.15))
        expect("全部关闭后停止后台指标采样", store.lastUpdated == stopped)

        if CommandLine.arguments.contains("--live"), let script = CommandLine.arguments.last {
            livePlayback(script: URL(fileURLWithPath: script))
        }
        if CommandLine.arguments.contains("--cold"), let script = CommandLine.arguments.last {
            let finished = DispatchSemaphore(value: 0)
            DispatchQueue.global().async {
                coldPlayback(script: URL(fileURLWithPath: script))
                finished.signal()
            }
            while finished.wait(timeout: .now()) != .success {
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
        }
        exit(failures == 0 ? 0 : 1)
    }

    static func livePlayback(script: URL) {
        let controller = SodaMusicController(scriptURL: script)
        guard let initial = controller.read().snapshot else {
            expect("汽水音乐正在提供歌曲元数据", false)
            return
        }
        print("实际歌曲：\(initial.title) · \(initial.artist)")
        let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        defer {
            _ = controller.send(initial.isPlaying ? .play : .pause)
        }
        for index in 1...3 {
            for (command, expected) in [(SodaMusicCommand.pause, false), (.play, true)] {
                let result = controller.send(command)
                switch result {
                case .success(let snapshot):
                    expect("第 \(index) 轮\(expected ? "播放" : "暂停")收到真实确认", snapshot.isPlaying == expected)
                case .failure(let error):
                    expect("第 \(index) 轮控制失败：\(error)", false)
                }
                let actual = controller.read().snapshot
                expect("回读播放器状态一致", actual?.isPlaying == expected)
            }
        }
        expect("播放控制不激活汽水音乐", foreground == NSWorkspace.shared.frontmostApplication?.processIdentifier)
    }

    static func coldPlayback(script: URL) {
        let controller = SodaMusicController(scriptURL: script)
        guard let initial = controller.read().snapshot,
              let application = NSRunningApplication.runningApplications(withBundleIdentifier: "com.soda.music").first else {
            expect("冷启动测试有可恢复的播放器会话", false)
            return
        }
        let previousApplication = NSWorkspace.shared.frontmostApplication
        defer {
            _ = controller.send(initial.isPlaying ? .play : .pause)
            previousApplication?.activate(options: [])
        }
        application.terminate()
        let deadline = Date().addingTimeInterval(3)
        while controller.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        guard !controller.isRunning else { expect("汽水音乐正常退出", false); return }
        expect("点击播放可启动汽水音乐", controller.launch())
        let error = controller.prepareSession()
        expect("冷启动无需手动播放即可建立媒体会话：\(error ?? "成功")", error == nil)
        if case .success(let snapshot) = controller.send(.play) {
            expect("冷启动播放返回实际歌曲和播放状态", snapshot.isPlaying && !snapshot.title.isEmpty)
        } else { expect("冷启动自动播放", false) }
    }
}
