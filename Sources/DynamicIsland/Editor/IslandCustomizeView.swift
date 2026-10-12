import SwiftUI

/// 仿 Safari「自定义工具栏」的灵动岛编辑面板：
/// 上方按真实比例预览岛屿，中间把组件库拖进槽位，下方微调几何，
/// 所有改动实时同步到屏幕上方真实的灵动岛。
struct IslandCustomizeView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var viewModel: IslandViewModel
    @EnvironmentObject var mediaPlayer: MediaPlayerStore
    @EnvironmentObject var metrics: SystemMetricsStore

    let onDone: () -> Void
    /// 预览态切换回调：true = 展开态，false = 收起态。驱动屏幕上方真实岛屿同步收起/展开。
    let onPreviewModeChanged: (Bool) -> Void

    @State private var previewMode: IslandPreviewMode = .expanded
    @State private var tab: CustomizeTab = .layout

    var body: some View {
        VStack(spacing: 0) {
            // 预览固定在顶部：参数怎么滚，舞台都和真实岛屿保持在视线里
            previewSection
            Divider()
            tabBar
            tabContent
            Divider()
            footer
        }
        .frame(width: 700, height: 780)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { onPreviewModeChanged(previewMode == .expanded) }
        .onChange(of: previewMode) { _, mode in
            onPreviewModeChanged(mode == .expanded)
        }
        .onChange(of: tab) { _, tab in
            // 进几何 tab 自动切到对应预览态：调收起态参数就看收起态，
            // 调展开态/动画参数就看展开态，不用手动切来切去。
            switch tab {
            case .compact: previewMode = .collapsed
            case .expanded, .motion: previewMode = .expanded
            case .layout: break
            }
        }
    }

    // MARK: - 实时预览

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("实时预览").font(.headline)
                Spacer()
                Text("屏幕上方真实岛屿同步更新").font(.caption).foregroundStyle(.tertiary)
                Picker("状态", selection: $previewMode) {
                    ForEach(IslandPreviewMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            IslandPreviewStage(mode: previewMode)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Tab 切换

    private var tabBar: some View {
        Picker("参数分类", selection: $tab) {
            ForEach(CustomizeTab.allCases) { item in
                Label(item.title, systemImage: item.symbol).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .layout:
            tabScroll { layoutTab }
        case .compact:
            tabScroll { compactTab }
        case .expanded:
            tabScroll { expandedTab }
        case .motion:
            tabScroll { motionTab }
        }
    }

    private func tabScroll<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content()
            }
            .padding(20)
        }
    }

    // MARK: - Tab：布局（槽位 + 组件库）

    private var layoutTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            slotSection
            paletteSection
        }
    }

    // MARK: - Tab：收起态参数

    private var compactTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("收起态 · 刘海带").font(.headline)

            CustomizeGroup("刘海带") {
                Toggle("自动匹配刘海", isOn: $settings.compactBandAutoSize)
                    .font(.system(size: 11))
                CustomizeSlider(
                    title: "宽度", value: $settings.compactBandWidth.doubleValue,
                    range: 80...900, step: 1, suffix: "pt"
                )
                .disabled(settings.compactBandAutoSize)
                CustomizeSlider(
                    title: "高度", value: $settings.compactBandHeight.doubleValue,
                    range: 20...80, step: 1, suffix: "pt"
                )
                .disabled(settings.compactBandAutoSize)
                CustomizeSlider(
                    title: "顶部圆角", value: $settings.compactBandTopRadius.doubleValue,
                    range: 0...40, step: 1, suffix: "pt"
                )
                CustomizeSlider(
                    title: "底部圆角", value: $settings.compactBandBottomRadius.doubleValue,
                    range: 0...40, step: 0.5, suffix: "pt"
                )
                CustomizeSlider(
                    title: "垂直偏移", value: $settings.compactBandYOffset.doubleValue,
                    range: -20...20, step: 1, suffix: "pt"
                )
                Text("圆角填 0 = 用自动值。")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            CustomizeGroup("收起动画") {
                CustomizeSlider(
                    title: "时长", value: $settings.collapseDuration,
                    range: 0.1...1.5, step: 0.01, suffix: "s"
                )
                CustomizeCurvePicker(title: "曲线", value: $settings.collapseTimingCurve, presets: TimingCurvePreset.collapsePresets)
            }
        }
    }

    // MARK: - Tab：展开态参数

    private var expandedTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("展开态 · 内容网格").font(.headline)

            CustomizeGroup("网格") {
                CustomizeSlider(
                    title: "图标大小", value: $settings.iconSize.doubleValue,
                    range: 32...90, step: 1, suffix: "px"
                )
                CustomizeStepper(title: "每行列数", value: $settings.columns, range: 3...12, suffix: "列")
                CustomizeSlider(
                    title: "图标间距", value: $settings.iconSpacing.doubleValue,
                    range: 4...30, step: 1, suffix: "px"
                )
                CustomizeSlider(
                    title: "左右边距", value: $settings.contentPadding.doubleValue,
                    range: 0...40, step: 1, suffix: "px"
                )
                CustomizeSlider(
                    title: "顶部间距", value: $settings.contentTopPadding.doubleValue,
                    range: 10...60, step: 1, suffix: "px"
                )
            }

            CustomizeGroup("形状") {
                CustomizeSlider(
                    title: "圆角", value: $settings.expandedCornerRadius.doubleValue,
                    range: 0...40, step: 1, suffix: "pt"
                )
                CustomizeSlider(
                    title: "整体上移", value: $settings.topBarYOffset.doubleValue,
                    range: 18...64, step: 1, suffix: "px"
                )
                CustomizeSlider(
                    title: "融合高度", value: $settings.topBarHeight.doubleValue,
                    range: 27...70, step: 1, suffix: "px"
                )
                CustomizeSlider(
                    title: "收缩宽度", value: $settings.compactWidth.doubleValue,
                    range: 90...240, step: 1, suffix: "px"
                )
                CustomizeSlider(
                    title: "收缩高度", value: $settings.compactHeight.doubleValue,
                    range: 1...10, step: 1, suffix: "px"
                )
            }

            HStack(spacing: 12) {
                Label("展开尺寸", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(settings.expandedWidth)) × \(Int(settings.expandedHeight)) pt")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Tab：动画

    private var motionTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("动画").font(.headline)

            CustomizeGroup("展开") {
                CustomizeSlider(
                    title: "时长", value: $settings.expandDuration,
                    range: 0.1...1.5, step: 0.01, suffix: "s"
                )
                CustomizeCurvePicker(title: "曲线", value: $settings.expandTimingCurve, presets: TimingCurvePreset.expandPresets)
            }

            CustomizeGroup("内容显示") {
                CustomizeSlider(
                    title: "淡入延迟", value: $settings.revealDelay,
                    range: 0...0.8, step: 0.01, suffix: "s"
                )
                CustomizeSlider(
                    title: "淡入时长", value: $settings.contentFadeInDuration,
                    range: 0...0.8, step: 0.01, suffix: "s"
                )
                CustomizeSlider(
                    title: "淡出时长", value: $settings.contentFadeOutDuration,
                    range: 0...0.5, step: 0.01, suffix: "s"
                )
                Text("鼠标移入即按展开动画播放，改完把鼠标在刘海附近晃动就能看效果。")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            CustomizeGroup("果冻融合") {
                CustomizeSlider(
                    title: "模糊半径", value: $settings.gooeyBlurRadius,
                    range: 0...30, step: 1, suffix: "px"
                )
                Text("模糊与融合高度联动：调大模糊，顶部融合高度会自动抬高。")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - 槽位

    private var slotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("槽位").font(.headline)
            slotRow(.topLeft)
            slotRow(.topRight)
            slotRow(.body)
        }
    }

    private func slotRow(_ slot: IslandSlot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(slot.title).font(.system(size: 11, weight: .semibold))
                Text(slot.hint).font(.system(size: 9)).foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                if !settings.components(in: slot).isEmpty {
                    Button("清空") { settings.clearSlot(slot) }
                        .font(.system(size: 10))
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                }
            }
            slotDropArea(slot)
        }
    }

    private func slotDropArea(_ slot: IslandSlot) -> some View {
        let ids = settings.components(in: slot)
        return FlowLayout(spacing: 6) {
            if ids.isEmpty {
                Text("把组件拖到这里")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
            }
            ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                componentChip(id, slot: slot, index: index)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 46, alignment: .leading)
        .modifier(SlotDropTarget(slot: slot))
    }

    private func componentChip(_ id: String, slot: IslandSlot, index: Int) -> some View {
        let descriptor = IslandComponentRegistry.descriptor(for: id)
        return HStack(spacing: 5) {
            Image(systemName: descriptor?.symbolName ?? "questionmark.square")
                .font(.system(size: 10))
            Text(descriptor?.title ?? id)
                .font(.system(size: 10, weight: .medium))
            Button {
                settings.removeComponent(id: id, from: slot)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .help("移除组件")
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.separator.opacity(0.35))
        )
        .draggable(IslandComponentTransfer(componentID: id, sourceSlot: slot))
        .dropDestination(for: IslandComponentTransfer.self) { items, _ in
            guard let transfer = items.first else { return false }
            settings.moveComponent(id: transfer.componentID, from: transfer.sourceSlot, to: slot, at: index)
            return true
        }
    }

    // MARK: - 组件库

    private var paletteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("组件库").font(.headline)
            Text("按住组件拖到上方的槽位里，真实岛屿会同步更新。").font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(IslandComponentRegistry.all, id: \.id) { descriptor in
                    paletteItem(descriptor)
                }
            }
        }
    }

    private func paletteItem(_ descriptor: IslandComponentDescriptor) -> some View {
        HStack(spacing: 8) {
            Image(systemName: descriptor.symbolName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(descriptor.title)
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.separator.opacity(0.3))
        )
        .draggable(IslandComponentTransfer(componentID: descriptor.id, sourceSlot: nil))
        .help("拖拽到槽位")
    }

    // MARK: - 底部

    private var footer: some View {
        HStack {
            Button("恢复默认布局") { settings.resetComponentLayout() }
            Spacer()
            Button("完成") { onDone() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - 参数分类 Tab

private enum CustomizeTab: String, CaseIterable, Identifiable {
    case layout
    case compact
    case expanded
    case motion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .layout: return "布局"
        case .compact: return "收起态"
        case .expanded: return "展开态"
        case .motion: return "动画"
        }
    }

    var symbol: String {
        switch self {
        case .layout: return "square.grid.2x2"
        case .compact: return "rectangle.compress.vertical"
        case .expanded: return "rectangle.expand.vertical"
        case .motion: return "timer"
        }
    }
}

// MARK: - 动画曲线预设

/// 贝塞尔曲线的常用档位，直接写控制点太反人类，给几个能听的预设。
private enum TimingCurvePreset: String, CaseIterable, Identifiable {
    case standard
    case linear
    case snappy
    case overshoot
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "默认"
        case .linear: return "线性"
        case .snappy: return "轻快"
        case .overshoot: return "回弹"
        case .custom: return "自定义"
        }
    }

    var points: String {
        switch self {
        case .standard: return "0.65, 0, 0.35, 1"
        case .linear: return "0, 0, 1, 1"
        case .snappy: return "0.25, 0.1, 0.25, 1"
        case .overshoot: return "0.34, 1.56, 0.64, 1"
        case .custom: return ""
        }
    }

    /// 当前设置命中哪个预设；没命中回 custom，保留用户已写死的控制点。
    static func match(_ value: String) -> TimingCurvePreset {
        allCases.first { $0.points == value } ?? .custom
    }

    static let expandPresets: [TimingCurvePreset] = [.standard, .snappy, .linear, .overshoot]
    static let collapsePresets: [TimingCurvePreset] = [.standard, .snappy, .linear, .overshoot]
}

private struct CustomizeCurvePicker: View {
    let title: String
    @Binding var value: String
    let presets: [TimingCurvePreset]

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 72, alignment: .leading)
            Picker(title, selection: selection) {
                ForEach(presets) { preset in
                    Text(preset.title).tag(preset)
                }
                if TimingCurvePreset.match(value) == .custom {
                    Text("自定义（\(value)）").tag(TimingCurvePreset.custom)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 11))
    }

    private var selection: Binding<TimingCurvePreset> {
        Binding(
            get: { TimingCurvePreset.match(value) },
            set: { preset in
                if preset != .custom { value = preset.points }
            }
        )
    }
}

// MARK: - 预览模式

private enum IslandPreviewMode: String, CaseIterable, Identifiable {
    case expanded
    case collapsed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expanded: return "展开态"
        case .collapsed: return "收起态"
        }
    }
}

// MARK: - 预览舞台

/// 一块「屏幕」：菜单栏 + 壁纸，岛屿挂在顶部正中间，按真实尺寸等比缩放。
private struct IslandPreviewStage: View {
    @EnvironmentObject var settings: SettingsStore

    let mode: IslandPreviewMode

    private let stageWidth: CGFloat = 620
    private let stageHeight: CGFloat = 340
    private let stageInset: CGFloat = 26
    private let menuBarHeight: CGFloat = 20

    var body: some View {
        let islandSize = mode == .expanded
            ? CGSize(width: settings.expandedWidth, height: settings.expandedHeight)
            : collapsedBandSize
        let scale = min(
            (stageWidth - stageInset * 2) / max(islandSize.width, 1),
            (stageHeight - menuBarHeight - stageInset) / max(islandSize.height, 1),
            1
        )

        ZStack(alignment: .top) {
            stageBackground

            VStack(spacing: 0) {
                stageMenuBar
                    .frame(height: menuBarHeight)
                Color.clear.frame(height: stageInset - menuBarHeight / 2)
                Group {
                    if mode == .expanded {
                        ExpandedIslandPreview()
                    } else {
                        CollapsedIslandPreview()
                    }
                }
                .scaleEffect(scale)
                .frame(width: max(islandSize.width * scale, 1), height: max(islandSize.height * scale, 1))
                Spacer(minLength: 0)
            }
        }
        .frame(width: stageWidth, height: stageHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.separator.opacity(0.4))
        )
    }

    private var stageBackground: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .underPageBackgroundColor),
                Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// 舞台顶部的假菜单栏，给岛屿一个环境参照。
    private var stageMenuBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "applelogo")
                .font(.system(size: 10))
            ForEach(0..<5, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(.primary.opacity(0.35))
                    .frame(width: index == 0 ? 26 : 14, height: 4)
            }
            Spacer(minLength: 0)
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(.primary.opacity(0.25))
                    .frame(width: 12, height: 4)
            }
        }
        .padding(.horizontal, 12)
        .foregroundStyle(.primary.opacity(0.5))
        .background(.primary.opacity(0.06))
    }

    /// 收起态刘海带的真实几何：自动模式下跟随系统刘海，手动模式用设置值。
    private var collapsedBandSize: CGSize {
        let notch = NotchDetector.current()
        let autoWidth = max(notch.frame.width, CompactMediaView.contentWidth)
        let width = settings.compactBandAutoSize ? autoWidth : settings.compactBandWidth
        let height = settings.compactBandAutoSize ? max(notch.frame.height, 1) : settings.compactBandHeight
        return CGSize(width: width, height: height)
    }
}

// MARK: - 展开态预览

/// 直接复用真实灵动岛的内容视图，保证预览与屏幕上方完全一致。
private struct ExpandedIslandPreview: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        IslandRootView()
            .frame(width: settings.expandedWidth, height: settings.expandedHeight)
            .background(
                Color.black,
                in: RoundedRectangle(cornerRadius: settings.expandedCornerRadius, style: .continuous)
            )
            .allowsHitTesting(false)
    }
}

// MARK: - 收起态预览

/// 收起态刘海带示意：黑色刘海形 + 头像 + 波纹，几何与真实紧凑带一致。
private struct CollapsedIslandPreview: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        let notch = NotchDetector.current()
        let width = settings.compactBandAutoSize
            ? max(notch.frame.width, CompactMediaView.contentWidth)
            : settings.compactBandWidth
        let height = settings.compactBandAutoSize ? max(notch.frame.height, 1) : settings.compactBandHeight
        let bottomRadius = settings.compactBandBottomRadius > 0
            ? settings.compactBandBottomRadius
            : height * NotchDetector.notchBottomRadiusRatio
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: settings.compactBandTopRadius,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: settings.compactBandTopRadius,
            style: .continuous
        )

        ZStack {
            shape.fill(.black)

            HStack(spacing: 10) {
                Circle()
                    .fill(.white.opacity(0.16))
                    .frame(width: 20, height: 20)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    )
                CompactBandWaveform()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
        }
        .frame(width: width, height: height)
        .clipShape(shape)
    }
}

/// 收起态波纹示意：随呼吸动画起伏的白色小柱。
private struct CompactBandWaveform: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 12.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    let phase = sin(t * 2.4 + Double(index) * 0.9)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(.white.opacity(0.85))
                        .frame(width: 2.5, height: 4 + abs(phase) * 12)
                }
            }
        }
    }
}

// MARK: - 拖拽目标修饰器

/// 槽位投放区：高亮边框 + 接收组件拖拽（追加到末尾）。
private struct SlotDropTarget: ViewModifier {
    @EnvironmentObject var settings: SettingsStore

    let slot: IslandSlot
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .background(
                (isTargeted ? Color.accentColor.opacity(0.14) : Color(nsColor: .quaternaryLabelColor).opacity(0.35)),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color(nsColor: .separatorColor).opacity(0.4),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            )
            .dropDestination(for: IslandComponentTransfer.self) { items, _ in
                guard let transfer = items.first else { return false }
                settings.moveComponent(id: transfer.componentID, from: transfer.sourceSlot, to: slot, at: nil)
                return true
            } isTargeted: { isTargeted = $0 }
    }
}

// MARK: - 通用控件

/// 简单流式布局：组件多时自动换行，不依赖系统 Flow。
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: min(x, maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

private struct CustomizeGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 10) {
                content
            }
            .padding(14)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.separator.opacity(0.3))
            )
        }
    }
}

private struct CustomizeSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String

    init(title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, suffix: String) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.suffix = suffix
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 72, alignment: .leading)
            Slider(value: $value, in: range, step: step)
            Text(formattedValue)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
        .font(.system(size: 11))
    }

    private var formattedValue: String {
        if step < 1 {
            return String(format: "%.1f%@", value, suffix)
        }
        return "\(Int(value.rounded()))\(suffix)"
    }
}

private struct CustomizeStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let suffix: String

    init(title: String, value: Binding<Int>, range: ClosedRange<Int>, suffix: String) {
        self.title = title
        self._value = value
        self.range = range
        self.suffix = suffix
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 72, alignment: .leading)
            Spacer(minLength: 0)
            Stepper("\(value) \(suffix)", value: $value, in: range)
                .font(.system(size: 11))
        }
        .font(.system(size: 11))
    }
}

private extension Binding where Value == CGFloat {
    var doubleValue: Binding<Double> {
        Binding<Double>(
            get: { Double(wrappedValue) },
            set: { wrappedValue = CGFloat($0) }
        )
    }
}
