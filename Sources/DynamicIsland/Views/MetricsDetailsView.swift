import SwiftUI
import Charts

final class MetricsPresentation: ObservableObject {
    @Published var selection: MetricsSection = .cpu
}

struct MetricsDetailsView: View {
    @ObservedObject var presentation: MetricsPresentation
    @ObservedObject private var metrics = SystemMetricsStore.shared

    private var isCPU: Bool { presentation.selection == .cpu }
    private var accent: Color { isCPU ? .blue : .teal }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Label("系统状态", systemImage: "waveform.path.ecg")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Picker("指标", selection: $presentation.selection) {
                        ForEach(MetricsSection.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 168)
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(usageText)
                        .font(.system(size: 40, weight: .medium, design: .rounded))
                        .monospacedDigit()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isCPU ? "CPU 使用率" : "内存使用率").font(.headline)
                        Text(isCPU ? metrics.processorName : memorySubtitle)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("最近 60 秒").font(.subheadline.weight(.medium))
                        Spacer()
                        Text("每秒刷新").font(.caption).foregroundStyle(.secondary)
                    }
                    if metrics.history.isEmpty {
                        ProgressView("正在采样…").frame(maxWidth: .infinity).frame(height: 144)
                    } else {
                        Chart(metrics.history) { sample in
                            let value = (isCPU ? sample.cpu : sample.memory) * 100
                            AreaMark(x: .value("时间", sample.date), y: .value("使用率", value))
                                .foregroundStyle(accent.opacity(0.12))
                            LineMark(x: .value("时间", sample.date), y: .value("使用率", value))
                                .foregroundStyle(accent)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                        .chartYScale(domain: 0...100)
                        .chartXScale(domain: chartRange)
                        .chartXAxis(.hidden)
                        .chartYAxis {
                            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                                AxisGridLine()
                                AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%").font(.caption2) }
                            }
                        }
                        .frame(height: 144)
                        .accessibilityLabel("\(presentation.selection.rawValue)最近一分钟使用率")
                    }
                }
                .padding(16)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                if isCPU { cpuDetails } else { memoryDetails }
                if let error = metrics.error {
                    Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Text(isCPU ? "使用率按全部逻辑核心合计归一到 100%。" : "使用率与内存压力不同，已用内存高不一定代表卡顿。")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("活动监视器") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                    }
                    .help("在活动监视器中查看各个进程")
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 480, minHeight: 530)
    }

    private var usageText: String {
        guard isCPU ? metrics.cpu != nil : metrics.memory != nil else { return "—" }
        return String(format: "%.0f%%", (isCPU ? metrics.cpuUsage : metrics.memoryUsage) * 100)
    }

    private var chartRange: ClosedRange<Date> {
        let end = metrics.lastUpdated ?? Date()
        return end.addingTimeInterval(-60)...end
    }

    private var memorySubtitle: String {
        guard let memory = metrics.memory else { return "正在读取内存信息" }
        return "已用 \(bytes(memory.used)) / 共 \(bytes(memory.total))"
    }

    private var cpuDetails: some View {
        Grid(horizontalSpacing: 24, verticalSpacing: 14) {
            row("用户进程", percentage(metrics.cpu?.user), "系统进程", percentage(metrics.cpu?.system))
            row("空闲", percentage(metrics.cpu?.idle), "逻辑核心", "\(metrics.coreCount) 核")
            row("温度状态", thermalText, "采样间隔", "1 秒")
        }
    }

    private var memoryDetails: some View {
        Grid(horizontalSpacing: 24, verticalSpacing: 14) {
            row("应用内存", bytes(metrics.memory?.app), "联线内存", bytes(metrics.memory?.wired))
            row("已压缩", bytes(metrics.memory?.compressed), "缓存文件", bytes(metrics.memory?.cached))
            row("可用内存", bytes(metrics.memory?.available), "已用交换空间", bytes(metrics.memory?.swap))
            row("内存压力", pressureText, "物理内存", bytes(metrics.memory?.total))
        }
    }

    private func row(_ first: String, _ firstValue: String, _ second: String, _ secondValue: String) -> some View {
        GridRow {
            detail(first, firstValue)
            detail(second, secondValue)
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.system(size: 12))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func bytes(_ value: UInt64?) -> String {
        value.map { ByteCountFormatter.string(fromByteCount: Int64(clamping: $0), countStyle: .memory) } ?? "—"
    }

    private func percentage(_ value: Double?) -> String {
        value.map { String(format: "%.1f%%", $0 * 100) } ?? "—"
    }

    private var pressureText: String {
        switch metrics.memory?.pressure {
        case 1: return "正常"
        case 2: return "偏高"
        case 4: return "紧张"
        default: return "暂不可用"
        }
    }

    private var thermalText: String {
        switch metrics.thermalState {
        case .nominal: return "正常"
        case .fair: return "略高"
        case .serious: return "偏高"
        case .critical: return "高温"
        @unknown default: return "未知"
        }
    }
}
