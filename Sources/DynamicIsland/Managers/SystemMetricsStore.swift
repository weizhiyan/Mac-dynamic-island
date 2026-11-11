import AppKit
import Combine
import Darwin

enum MetricsSection: String, CaseIterable, Identifiable {
    case cpu = "CPU"
    case memory = "内存"
    var id: Self { self }
}

struct MetricsSample: Identifiable {
    let date: Date
    let cpu: Double
    let memory: Double
    var id: Date { date }
}

struct CPUBreakdown {
    let user: Double
    let system: Double
    let idle: Double
    var usage: Double { min(1, max(0, user + system)) }

    static func between(_ previous: [UInt32], _ current: [UInt32]) -> CPUBreakdown? {
        guard previous.count == 4, current.count == 4 else { return nil }
        let delta = zip(current, previous).map { Double($0 &- $1) }
        let total = delta.reduce(0, +)
        guard total > 0 else { return nil }
        return CPUBreakdown(user: (delta[0] + delta[3]) / total, system: delta[1] / total, idle: delta[2] / total)
    }
}

struct MemoryBreakdown {
    let total: UInt64
    let app: UInt64
    let wired: UInt64
    let compressed: UInt64
    let cached: UInt64
    let swap: UInt64
    let pressure: Int?
    var used: UInt64 { min(total, app + wired + compressed) }
    var usage: Double { total > 0 ? Double(used) / Double(total) : 0 }
    var available: UInt64 { total - used }

    static func make(total: UInt64, pageSize: UInt64, internalPages: UInt64, purgeablePages: UInt64, wiredPages: UInt64, compressedPages: UInt64, externalPages: UInt64, swap: UInt64, pressure: Int?) -> Self {
        Self(total: total, app: (internalPages - min(internalPages, purgeablePages)) * pageSize,
             wired: wiredPages * pageSize, compressed: compressedPages * pageSize,
             cached: (externalPages + purgeablePages) * pageSize, swap: swap, pressure: pressure)
    }
}

final class SystemMetricsStore: ObservableObject {
    static let shared = SystemMetricsStore()
    @Published private(set) var cpu: CPUBreakdown?
    @Published private(set) var memory: MemoryBreakdown?
    @Published private(set) var history: [MetricsSample] = []
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var error: String?
    @Published private(set) var thermalState = ProcessInfo.processInfo.thermalState
    var cpuUsage: Double { cpu?.usage ?? 0 }
    var memoryUsage: Double { memory?.usage ?? 0 }
    let coreCount = ProcessInfo.processInfo.processorCount
    let processorName: String

    private let queue = DispatchQueue(label: "dynamic-island.metrics", qos: .utility)
    private var timer: DispatchSourceTimer?
    private let hostPort = mach_host_self()
    private var previousTicks: [UInt32]?
    private var consumers = Set<String>()
    private var sleeping = false
    private var observers: [NSObjectProtocol] = []

    private init() {
        var length = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &length, nil, 0)
        var name = [CChar](repeating: 0, count: max(1, length))
        processorName = sysctlbyname("machdep.cpu.brand_string", &name, &length, nil, 0) == 0 ? String(cString: name) : "处理器"
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { self?.sleeping = true; self?.updateSampling() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { self?.sleeping = false; self?.updateSampling() }
        })
    }

    deinit {
        timer?.cancel()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        mach_port_deallocate(mach_task_self_, hostPort)
    }

    func setActive(_ active: Bool, consumer: String = "island") {
        queue.async { [weak self] in
            guard let self else { return }
            if active { self.consumers.insert(consumer) } else { self.consumers.remove(consumer) }
            self.updateSampling()
        }
    }

    private func updateSampling() {
        guard !consumers.isEmpty, !sleeping else {
            timer?.cancel()
            timer = nil
            previousTicks = nil
            return
        }
        guard timer == nil else { return }
        previousTicks = readTicks()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.15, repeating: 1, leeway: .milliseconds(120))
        timer.setEventHandler { [weak self] in self?.refresh() }
        self.timer = timer
        timer.resume()
    }

    private func refresh() {
        let ticks = readTicks()
        let cpu = previousTicks.flatMap { previous in ticks.flatMap { CPUBreakdown.between(previous, $0) } }
        previousTicks = ticks
        let memory = readMemory()
        let now = Date()
        let thermal = ProcessInfo.processInfo.thermalState
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.cpu = cpu
            self.memory = memory
            self.thermalState = thermal
            self.error = cpu == nil || memory == nil ? "暂时无法读取部分系统数据" : nil
            self.lastUpdated = now
            if let cpu, let memory {
                self.history.append(MetricsSample(date: now, cpu: cpu.usage, memory: memory.usage))
                self.history.removeAll { now.timeIntervalSince($0.date) > 60 }
            }
        }
    }

    private func readTicks() -> [UInt32]? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(hostPort, HOST_CPU_LOAD_INFO, $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        return [info.cpu_ticks.0, info.cpu_ticks.1, info.cpu_ticks.2, info.cpu_ticks.3]
    }

    private func readMemory() -> MemoryBreakdown? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(hostPort, HOST_VM_INFO64, $0, &count) }
        }
        var pageSize: vm_size_t = 0
        guard result == KERN_SUCCESS, host_page_size(hostPort, &pageSize) == KERN_SUCCESS else { return nil }
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0)
        var pressure: Int32 = 0
        var pressureSize = MemoryLayout<Int32>.size
        let hasPressure = sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &pressureSize, nil, 0) == 0
        return .make(total: ProcessInfo.processInfo.physicalMemory, pageSize: UInt64(pageSize),
                     internalPages: UInt64(stats.internal_page_count), purgeablePages: UInt64(stats.purgeable_count),
                     wiredPages: UInt64(stats.wire_count), compressedPages: UInt64(stats.compressor_page_count),
                     externalPages: UInt64(stats.external_page_count), swap: swap.xsu_used, pressure: hasPressure ? Int(pressure) : nil)
    }
}
