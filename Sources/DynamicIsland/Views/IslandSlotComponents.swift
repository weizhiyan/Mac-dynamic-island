import SwiftUI
import IOKit.ps

/// 时间 + 日期，一行极简文本，供顶栏与内容区共用。
struct IslandClockView: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 6) {
                Text(Self.timeFormatter.string(from: context.date))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.92))
                Text(Self.dateFormatter.string(from: context.date))
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .fixedSize()
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日 EEE"
        return formatter
    }()
}

/// 电池电量。台式机没有电池时整体不占位。
struct IslandBatteryView: View {
    var body: some View {
        if let info = Self.readBattery() {
            HStack(spacing: 4) {
                Image(systemName: info.charging ? "battery.100.bolt" : Self.symbol(level: info.level))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                Text("\(info.level)%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.88))
            }
            .fixedSize()
        }
    }

    private static func symbol(level: Int) -> String {
        switch level {
        case 75...: return "battery.100"
        case 50...: return "battery.75"
        case 25...: return "battery.50"
        default: return "battery.25"
        }
    }

    private static func readBattery() -> (level: Int, charging: Bool)? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  // 只认内置电池：台式机/外接 UPS 不显示
                  (description[kIOPSTypeKey] as? String) == "InternalBattery",
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0 else { continue }
            let charging = (description[kIOPSIsChargingKey] as? Bool) ?? false
            return (Int((Double(current) / Double(maximum)) * 100.0), charging)
        }
        return nil
    }
}

/// 固定间距：顶栏槽位里是横向空隙，内容区里是纵向空隙。
struct IslandFixedSpacer: View {
    let vertical: Bool

    var body: some View {
        Color.clear.frame(width: vertical ? 1 : 16, height: vertical ? 12 : 1)
    }
}

/// 可调间距：在所在轴向上把其他组件推开。
struct IslandFlexibleSpacer: View {
    var body: some View {
        Spacer(minLength: 0)
    }
}
