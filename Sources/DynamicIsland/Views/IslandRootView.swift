import SwiftUI

struct IslandRootView: View {
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var viewModel: IslandViewModel

    var body: some View {
        ZStack(alignment: .top) {
            AppGrid()
                .padding(.top, settings.effectiveContentTopPadding)
                .padding(.horizontal, settings.contentPadding)
                .padding(.bottom, settings.contentPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            IslandTopControls()
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct IslandTopControls: View {
    @EnvironmentObject var settings: SettingsStore

    private let controlSize: CGFloat = 24
    private let iconSize: CGFloat = 12
    private let controlSpacing: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let maxGap = max(24, proxy.size.width - controlSize * 2 - controlSpacing * 2)
            let notchGap = min(settings.compactWidth, maxGap)

            HStack(spacing: controlSpacing) {
                IslandControlButton(symbol: "gearshape") {
                    AppDelegate.shared?.openSettings()
                }
                .help("设置")

                Color.clear
                    .frame(width: notchGap, height: controlSize)

                IslandControlButton(symbol: "plus") {
                    AppDelegate.shared?.addShortcutAppsFromPanel()
                }
                .help("添加应用")
            }
            .frame(width: proxy.size.width, height: controlSize, alignment: .center)
        }
        .frame(height: controlSize)
    }
}

private struct IslandControlButton: View {
    let symbol: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(isHovered ? 0.92 : 0.72))
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background {
            Circle()
                .fill(.ultraThinMaterial)
            Circle()
                .fill(Color.white.opacity(isHovered ? 0.14 : 0.08))
        }
        .clipShape(Circle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
