import SwiftUI

struct AppGrid: View {
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var viewModel: IslandViewModel

    var body: some View {
        let apps = appStore.apps.sorted(by: { $0.order < $1.order })
        let cols = max(1, settings.columns)
        let rows = Int(ceil(Double(apps.count) / Double(cols)))
        return VStack(spacing: settings.iconSpacing) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: settings.iconSpacing) {
                    ForEach(0..<cols, id: \.self) { c in
                        let idx = r * cols + c
                        if idx < apps.count {
                            AppIconView(item: apps[idx], size: settings.iconSize, reveal: viewModel.isExpanded)
                        } else {
                            // 占位保持网格对齐
                            Color.clear.frame(width: settings.iconSize, height: settings.iconSize)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
