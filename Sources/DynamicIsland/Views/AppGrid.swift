import SwiftUI

struct AppGrid: View {
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var viewModel: IslandViewModel
    @State private var hoverLocation: CGPoint?
    @State private var draggedApp: AppItem?
    @State private var lastInsertionKey: String?
    @State private var dragJustEnded = false

    var body: some View {
        let apps = appStore.visibleApps()
        let cols = max(1, settings.columns)
        let rows = Int(ceil(Double(apps.count) / Double(cols)))
        return VStack(spacing: settings.iconSpacing) {
            ForEach(0..<rows, id: \.self) { row in
                let start = row * cols
                let end = min(start + cols, apps.count)
                let rowApps = Array(apps[start..<end])
                HStack(spacing: settings.iconSpacing) {
                    ForEach(rowApps) { item in
                        let index = apps.firstIndex(where: { $0.id == item.id }) ?? start
                        let column = index - start
                        AppIconView(
                            item: item,
                            size: settings.iconSize,
                            reveal: viewModel.isExpanded,
                            magnification: magnification(row: row, column: column),
                            isDragging: draggedApp?.id == item.id,
                            onTap: {
                                guard draggedApp == nil, !dragJustEnded else { return }
                                ClickProbe.log("onTapGesture \(item.name)")
                                AppLauncher.launch(item)
                            }
                        )
                        .zIndex(draggedApp?.id == item.id ? 100 : magnification(row: row, column: column))
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 8, coordinateSpace: .named("app-grid"))
                                .onChanged { value in
                                    if draggedApp == nil {
                                        draggedApp = item
                                        lastInsertionKey = nil
                                        dragJustEnded = false
                                    }
                                    guard draggedApp?.id == item.id else { return }
                                    dragJustEnded = true
                                    reorderDraggedApp(at: value.location, columns: cols)
                                }
                                .onEnded { _ in
                                    draggedApp = nil
                                    lastInsertionKey = nil
                                    DispatchQueue.main.async {
                                        dragJustEnded = false
                                    }
                                }
                        )
                    }
                    ForEach(rowApps.count..<cols, id: \.self) { _ in
                        Color.clear.frame(width: settings.iconSize, height: settings.iconSize)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private func reorderDraggedApp(at location: CGPoint, columns: Int) {
        guard let draggedApp else { return }
        let apps = appStore.visibleApps()
        guard apps.count > 1 else { return }

        let pitch = settings.iconSize + settings.iconSpacing
        guard pitch > 0 else { return }
        let row = max(0, Int(floor(location.y / pitch)))
        let column = max(0, Int(floor(location.x / pitch)))
        let targetIndex = min(row * columns + column, apps.count - 1)
        let target = apps[targetIndex]
        guard target.id != draggedApp.id else { return }

        let localX = location.x - CGFloat(column) * pitch
        let insertAfter = localX > settings.iconSize / 2
        let insertionKey = "\(target.id.uuidString)-\(insertAfter)"
        guard lastInsertionKey != insertionKey else { return }
        lastInsertionKey = insertionKey

        withAnimation(.interactiveSpring(response: 0.20, dampingFraction: 0.86)) {
            appStore.moveApp(draggedApp, relativeTo: target, after: insertAfter)
        }
    }
}
