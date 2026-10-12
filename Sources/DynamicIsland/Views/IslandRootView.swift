import SwiftUI

struct IslandRootView: View {
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var viewModel: IslandViewModel

    var body: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(settings.bodyComponents, id: \.self) { id in
                    IslandComponentRegistry.content(for: id, slot: .body)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, settings.effectiveContentTopPadding)
            .padding(.horizontal, settings.contentPadding)
            .padding(.bottom, settings.contentPadding)

            IslandTopControls()
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

struct MediaControlButton: View {
    let symbol: String
    let help: String
    var showsProgress = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if showsProgress {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white.opacity(0.8))
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(isHovered ? 1 : 0.75))
                }
            }
            .frame(width: 23, height: 27)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovered ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help(help)
        .accessibilityLabel(help)
        .onHover { isHovered = $0 }
    }
}

/// 展开态顶栏：刘海左右两侧按槽位配置渲染组件，中间留出物理刘海的宽度。
/// 自定义面板的实时预览直接复用本视图，保证预览与真实岛屿一致。
struct IslandTopControls: View {
    @EnvironmentObject var settings: SettingsStore

    private let controlSize: CGFloat = 24
    private let controlSpacing: CGFloat = 4
    /// 摘要两侧各自至少能用的宽度。
    private let minimumSideWidth: CGFloat = 60

    var body: some View {
        GeometryReader { proxy in
            let maxGap = max(24, proxy.size.width - minimumSideWidth * 2)
            let notchGap = min(max(settings.compactWidth, NotchDetector.current().frame.width + 8), maxGap)

            HStack(spacing: controlSpacing) {
                componentRow(settings.topLeftComponents, alignment: .leading, slot: .topLeft)

                Color.clear
                    .frame(width: notchGap, height: controlSize)

                componentRow(settings.topRightComponents, alignment: .trailing, slot: .topRight)
            }
            .padding(.horizontal, 10)
            .frame(width: proxy.size.width, height: controlSize, alignment: .center)
        }
        .frame(height: controlSize)
    }

    private func componentRow(_ ids: [String], alignment: Alignment, slot: IslandSlot) -> some View {
        HStack(spacing: 8) {
            ForEach(ids, id: \.self) { id in
                IslandComponentRegistry.content(for: id, slot: slot)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }
}

/// 刘海左侧：头像 + 歌名 · 艺术家 + 播放暂停，一行截断，不做卡片。
struct MusicMiniSummary: View {
    @EnvironmentObject private var mediaPlayer: MediaPlayerStore

    var body: some View {
        HStack(spacing: 6) {
            MiniAvatar(image: mediaPlayer.avatarImage)

            Text(summaryLine)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(mediaPlayer.track == nil ? AnyShapeStyle(.white.opacity(0.5)) : AnyShapeStyle(.white.opacity(0.88)))
                .lineLimit(1)
                .truncationMode(.tail)

            MediaControlButton(
                symbol: mediaPlayer.playbackState == .playing ? "pause.fill" : "play.fill",
                help: mediaPlayer.playbackState == .playing ? "暂停" : "播放",
                showsProgress: mediaPlayer.isBusy,
                action: mediaPlayer.togglePlayPause
            )
            .disabled(mediaPlayer.isBusy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(mediaPlayer.lastError ?? mediaPlayer.track?.title ?? "播放")
    }

    private var summaryLine: String {
        guard let track = mediaPlayer.track else { return mediaPlayer.primaryStatusText }
        return "\(track.title) · \(track.artist)"
    }
}

struct MiniAvatar: View {
    let image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.08))
            }
        }
        .frame(width: 18, height: 18)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .allowsHitTesting(false)
    }
}

/// 刘海右侧：CPU 与内存百分比，同样一行纯文本。
struct MetricsMiniSummary: View {
    @EnvironmentObject private var metrics: SystemMetricsStore

    var body: some View {
        HStack(spacing: 9) {
            MiniMetric(title: "CPU", value: metrics.cpuUsage)
            MiniMetric(title: "内存", value: metrics.memoryUsage)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .allowsHitTesting(false)
    }
}

struct MiniMetric: View {
    let title: String
    let value: Double

    var body: some View {
        HStack(spacing: 3) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.42))
            Text("\(Int(value * 100))%")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.88))
        }
    }
}
