import SwiftUI

/// 组件槽位：展开态顶栏刘海左右两侧 + 展开态内容区。
enum IslandSlot: String, CaseIterable, Codable {
    case topLeft
    case topRight
    case body

    var title: String {
        switch self {
        case .topLeft: return "顶部 · 左侧"
        case .topRight: return "顶部 · 右侧"
        case .body: return "内容区"
        }
    }

    var hint: String {
        switch self {
        case .topLeft, .topRight: return "刘海两侧，只放极简内容"
        case .body: return "展开态主体，可堆叠多个组件"
        }
    }
}

/// 组件描述符。新增组件 = 实现视图 + 在 `IslandComponentRegistry.all` 里登记一条，
/// 自定义面板、真实灵动岛与预览会同时认到它。
struct IslandComponentDescriptor {
    let id: String
    let title: String
    let symbolName: String
    /// 内容区里占用的高度（pt）。返回 nil 表示高度动态（如应用网格）。
    let bodyHeight: CGFloat?
    let allowsTopSlot: Bool
    let allowsBodySlot: Bool
    /// 真实视图。slot 决定同一组件在不同槽位里的形态（如间距组件的横竖方向）。
    let makeContent: (IslandSlot) -> AnyView

    init(
        id: String,
        title: String,
        symbolName: String,
        bodyHeight: CGFloat? = 24,
        allowsTopSlot: Bool = true,
        allowsBodySlot: Bool = true,
        makeContent: @escaping (IslandSlot) -> AnyView
    ) {
        self.id = id
        self.title = title
        self.symbolName = symbolName
        self.bodyHeight = bodyHeight
        self.allowsTopSlot = allowsTopSlot
        self.allowsBodySlot = allowsBodySlot
        self.makeContent = makeContent
    }
}

/// 组件注册表：灵动岛与自定义面板唯一认的组件来源。
enum IslandComponentRegistry {
    static let musicSummaryID = "music-summary"
    static let metricsSummaryID = "metrics-summary"
    static let clockID = "clock"
    static let batteryID = "battery"
    static let fixedSpacerID = "fixed-spacer"
    static let flexibleSpacerID = "flexible-spacer"
    static let appGridID = "app-grid"

    /// 全部可添加组件。后期新增组件只需要往这个数组里加一项。
    static let all: [IslandComponentDescriptor] = [
        IslandComponentDescriptor(
            id: musicSummaryID, title: "音乐摘要", symbolName: "music.note", bodyHeight: 30
        ) { _ in AnyView(MusicMiniSummary()) },
        IslandComponentDescriptor(
            id: metricsSummaryID, title: "性能摘要", symbolName: "cpu", bodyHeight: 24
        ) { _ in AnyView(MetricsMiniSummary()) },
        IslandComponentDescriptor(
            id: clockID, title: "时钟", symbolName: "clock", bodyHeight: 24
        ) { _ in AnyView(IslandClockView()) },
        IslandComponentDescriptor(
            id: batteryID, title: "电池", symbolName: "battery.100.bolt", bodyHeight: 24
        ) { _ in AnyView(IslandBatteryView()) },
        IslandComponentDescriptor(
            id: fixedSpacerID, title: "固定间距", symbolName: "space", bodyHeight: 12
        ) { slot in AnyView(IslandFixedSpacer(vertical: slot == .body)) },
        IslandComponentDescriptor(
            id: flexibleSpacerID, title: "可调间距", symbolName: "arrow.left.and.right", bodyHeight: 0
        ) { _ in AnyView(IslandFlexibleSpacer()) },
        IslandComponentDescriptor(
            id: appGridID, title: "应用网格", symbolName: "square.grid.2x2", bodyHeight: nil,
            allowsTopSlot: false
        ) { _ in AnyView(AppGrid()) }
    ]

    static func descriptor(for id: String) -> IslandComponentDescriptor? {
        all.first { $0.id == id }
    }

    /// 渲染槽位里的一个组件；未知 id 返回空视图（配置里已删除的组件不会崩）。
    static func content(for id: String, slot: IslandSlot) -> AnyView {
        guard let descriptor = descriptor(for: id) else { return AnyView(EmptyView()) }
        return descriptor.makeContent(slot)
    }

    /// 内容区高度：应用网格按实际行列动态算，其余组件用登记值。
    static func bodyHeight(for id: String, iconGridHeight: CGFloat) -> CGFloat {
        guard id != appGridID else { return iconGridHeight }
        return descriptor(for: id)?.bodyHeight ?? 0
    }

    /// 组件在某槽位是否可用。
    static func allows(_ id: String, in slot: IslandSlot) -> Bool {
        guard let descriptor = descriptor(for: id) else { return false }
        switch slot {
        case .topLeft, .topRight: return descriptor.allowsTopSlot
        case .body: return descriptor.allowsBodySlot
        }
    }
}

/// 拖拽转移载荷：组件 id + 来源槽位（nil 表示从组件库新增）。
struct IslandComponentTransfer: Codable, Transferable {
    let componentID: String
    let sourceSlot: IslandSlot?

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .plainText)
    }
}
