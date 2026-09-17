import SwiftUI
import UniformTypeIdentifiers

struct AppGrid: View {
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var viewModel: IslandViewModel
    @State private var hoverLocation: CGPoint?
    @State private var draggedApp: AppItem?

    var body: some View {
        let apps = appStore.visibleApps(for: settings.appFilterMode)
        let cols = max(1, settings.columns)
        let rows = Int(ceil(Double(apps.count) / Double(cols)))
        return VStack(spacing: settings.iconSpacing) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: settings.iconSpacing) {
                    ForEach(0..<cols, id: \.self) { column in
                        let index = row * cols + column
                        if index < apps.count {
                            AppIconView(
                                item: apps[index],
                                size: settings.iconSize,
                                reveal: viewModel.isExpanded,
                                magnification: magnification(row: row, column: column)
                            )
                            .zIndex(magnification(row: row, column: column))
                            .onDrag {
                                draggedApp = apps[index]
                                return NSItemProvider(object: apps[index].id.uuidString as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: AppGridDropDelegate(
                                    target: apps[index],
                                    draggedApp: $draggedApp,
                                    appStore: appStore
                                )
                            )
                        } else {
                            Color.clear.frame(width: settings.iconSize, height: settings.iconSize)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .coordinateSpace(name: "app-grid")
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                hoverLocation = location
            case .ended:
                hoverLocation = nil
            }
        }
        .animation(.spring(response: 0.18, dampingFraction: 0.82), value: hoverLocation)
    }

    private func magnification(row: Int, column: Int) -> CGFloat {
        guard viewModel.isExpanded, let hoverLocation else { return 1 }

        let pitch = settings.iconSize + settings.iconSpacing
        let center = CGPoint(
            x: CGFloat(column) * pitch + settings.iconSize / 2,
            y: CGFloat(row) * pitch + settings.iconSize / 2
        )
        let dx = hoverLocation.x - center.x
        let dy = hoverLocation.y - center.y
        let distance = hypot(dx, dy)
        let radius = max(settings.iconSize * 1.85, 96)
        guard distance < radius else { return 1 }

        let influence = 1 - distance / radius
        let eased = influence * influence * (3 - 2 * influence)
        return 1 + eased * 0.28
    }
}

private struct AppGridDropDelegate: DropDelegate {
    let target: AppItem
    @Binding var draggedApp: AppItem?
    let appStore: AppStore

    func dropEntered(info: DropInfo) {
        guard let draggedApp, draggedApp.id != target.id else { return }
        appStore.moveApp(draggedApp, before: target)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedApp = nil
        return true
    }
}
