import SwiftUI

struct MusicDetailsView: View {
    @ObservedObject private var media = MediaPlayerStore.shared
    @ObservedObject var presentation: MusicPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Group {
                    if let image = media.avatarImage {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "music.note").font(.title).frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.secondary.opacity(0.1))
                    }
                }
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(media.track?.title ?? media.primaryStatusText)
                        .font(.headline).lineLimit(2).textSelection(.enabled)
                    Text(media.track?.artist ?? media.selectedOption?.title ?? "未绑定播放器")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    if let album = media.track?.album, !album.isEmpty {
                        Text(album).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            if media.duration > 0 {
                if presentation.isVisible && media.playbackState == .playing {
                    TimelineView(.periodic(from: .now, by: 1)) { context in progress(at: context.date) }
                } else {
                    progress(at: media.sampledAt)
                }
            }
            HStack(spacing: 20) {
                Spacer()
                Button(action: media.previousTrack) {
                    Image(systemName: "backward.end.fill").frame(width: 36, height: 32)
                }
                .help("上一首").accessibilityLabel("上一首")
                .disabled(media.isBusy || media.track == nil)
                Button(action: media.togglePlayPause) {
                    HStack(spacing: 8) {
                        if media.isBusy { ProgressView().controlSize(.small) }
                        else { Image(systemName: media.playbackControlSymbol) }
                        Text(media.isBusy ? "正在连接" : media.playbackControlTitle)
                    }
                    .frame(width: 128, height: 32)
                }
                .buttonStyle(.borderedProminent)
                .help(media.playbackControlTitle)
                .accessibilityLabel(media.playbackControlTitle)
                .disabled(media.isBusy)
                .keyboardShortcut(.space, modifiers: [])
                Button(action: media.nextTrack) {
                    Image(systemName: "forward.end.fill").frame(width: 36, height: 32)
                }
                .help("下一首").accessibilityLabel("下一首")
                .disabled(media.isBusy || media.track == nil)
                Spacer()
            }
            if let error = media.lastError {
                VStack(alignment: .leading, spacing: 10) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("重试连接", action: media.retryConnection).disabled(media.isBusy)
                        if media.permissionRequired { Button("前往授权", action: media.openPermissionSettings) }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            HStack {
                Text(media.selectedOption?.title ?? "选择播放器后即可播放")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("打开播放器", action: media.openPlayer)
                    .disabled(media.selectedOption == nil)
                Button("播放器设置") { AppDelegate.shared?.openSettings() }
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func progress(at date: Date) -> some View {
        let elapsed = min(media.duration, media.elapsedTime + (media.playbackState == .playing ? max(0, date.timeIntervalSince(media.sampledAt)) : 0))
        return VStack(spacing: 6) {
            ProgressView(value: elapsed, total: media.duration).tint(.secondary)
                .accessibilityLabel("播放进度")
                .accessibilityValue("\(time(elapsed))，共\(time(media.duration))")
            HStack {
                Text(time(elapsed))
                Spacer()
                Text(time(media.duration))
            }
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func time(_ seconds: TimeInterval) -> String {
        let value = Int(max(0, seconds))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
