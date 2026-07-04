import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var appStore: AppStore
    @State private var selectedPane: SettingsPane? = .overview
    @State private var draggedApp: AppItem?

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedPane) {
                Section("设置") {
                    ForEach(SettingsPane.allCases) { pane in
                        Label(pane.title, systemImage: pane.symbol)
                            .tag(pane)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 250)
            .listStyle(.sidebar)
        } detail: {
            ScrollView {
                paneContent
                    .frame(maxWidth: 680, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 760, minHeight: 560)
    }

    @ViewBuilder
    private var paneContent: some View {
        switch selectedPane ?? .overview {
        case .overview:
            overviewPane
        case .appearance:
            appearancePane
        case .trigger:
            triggerPane
        case .animation:
            animationPane
        }
    }

    private var overviewPane: some View {
        SettingsPage(title: "基础设置", subtitle: "管理快捷应用，并调整岛屿展开后的基础布局。") {
            appManagementSection

            HStack(spacing: 12) {
                MetricTile(title: "快捷应用", value: "\(appStore.apps.count)", symbol: "app")
                MetricTile(title: "展开尺寸", value: "\(Int(settings.expandedWidth)) x \(Int(settings.expandedHeight))", symbol: "arrow.up.left.and.arrow.down.right")
                MetricTile(title: "触发区", value: "\(Int(settings.hoverZoneWidth)) x \(Int(settings.hoverZoneHeight))", symbol: "cursorarrow")
            }

            SettingsGroup("常用调整") {
                SliderSetting(title: "图标大小", value: $settings.iconSize.doubleValue, range: 32...72, step: 1, suffix: "px")
                StepperSetting(title: "每行列数", value: $settings.columns, range: 3...8, suffix: "列")
                SliderSetting(title: "图标间距", value: $settings.iconSpacing.doubleValue, range: 6...24, step: 1, suffix: "px")
                SliderSetting(title: "顶部内边距", value: $settings.contentTopPadding.doubleValue, range: 10...46, step: 1, suffix: "px")
            }

            SettingsGroup("维护") {
                HStack {
                    Label("恢复所有参数到默认值", systemImage: "arrow.counterclockwise")
                    Spacer()
                    Button("恢复默认") {
                        settings.restoreDefaults()
                    }
                }
                HStack {
                    Label("恢复默认快捷应用", systemImage: "square.grid.2x2")
                    Spacer()
                    Button("恢复应用") {
                        appStore.restoreDefaultApps()
                    }
                }
            }
        }
    }

    private var appManagementSection: some View {
        SettingsGroup("应用") {
            HStack {
                Text("\(appStore.apps.count) 个应用")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    openAppPicker()
                } label: {
                    Label("添加应用", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            let sortedApps = appStore.apps.sorted(by: { $0.order < $1.order })
            if sortedApps.isEmpty {
                EmptyState(title: "还没有快捷应用", symbol: "app")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 88, maximum: 108), spacing: 12)], alignment: .leading, spacing: 12) {
                    ForEach(sortedApps) { app in
                        AppTile(app: app, isDragging: draggedApp?.id == app.id) {
                            appStore.removeApp(app)
                        }
                        .onDrag {
                            draggedApp = app
                            return NSItemProvider(object: app.id.uuidString as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: AppTileDropDelegate(target: app, draggedApp: $draggedApp, appStore: appStore)
                        )
                    }
                }
                .animation(.easeInOut(duration: 0.16), value: sortedApps)
            }
        }
    }

    private func openAppPicker() {
        let panel = NSOpenPanel()
        panel.title = "选择应用"
        panel.prompt = "添加"
        panel.message = "可以一次选择多个应用"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true

        if panel.runModal() == .OK {
            appStore.addApps(at: panel.urls)
        }
    }

    private var appearancePane: some View {
        SettingsPage(title: "外观布局", subtitle: "调整收缩态、展开态和内容网格的视觉尺寸。") {
            SettingsGroup("应用网格") {
                SliderSetting(title: "图标大小", value: $settings.iconSize.doubleValue, range: 32...72, step: 1, suffix: "px")
                StepperSetting(title: "每行列数", value: $settings.columns, range: 3...8, suffix: "列")
                SliderSetting(title: "图标间距", value: $settings.iconSpacing.doubleValue, range: 6...24, step: 1, suffix: "px")
                SliderSetting(title: "顶部内边距", value: $settings.contentTopPadding.doubleValue, range: 10...46, step: 1, suffix: "px")
            }

            SettingsGroup("岛屿形状") {
                SliderSetting(title: "收缩宽度", value: $settings.compactWidth.doubleValue, range: 90...240, step: 1, suffix: "px")
                SliderSetting(title: "收缩高度", value: $settings.compactHeight.doubleValue, range: 1...10, step: 1, suffix: "px")
                SliderSetting(title: "顶部融合高度", value: $settings.topBarHeight.doubleValue, range: 27...70, step: 1, suffix: "px")
                SliderSetting(title: "整体上移", value: $settings.topBarYOffset.doubleValue, range: 18...54, step: 1, suffix: "px")
            }
        }
    }

    private var triggerPane: some View {
        SettingsPage(title: "触发方式", subtitle: "控制鼠标靠近顶部刘海时的触发区域和响应延迟。") {
            SettingsGroup("触发区域") {
                HStack {
                    Label("显示当前触发区域", systemImage: "eye")
                    Spacer()
                    Button("显示触发区域") {
                        AppDelegate.shared?.showTriggerAreaPreview()
                    }
                }
                SliderSetting(title: "区域宽度", value: $settings.hoverZoneWidth.doubleValue, range: 120...360, step: 1, suffix: "px")
                SliderSetting(title: "区域高度", value: $settings.hoverZoneHeight.doubleValue, range: 3...24, step: 1, suffix: "px")
                SliderSetting(title: "纵向偏移", value: $settings.hoverZoneYOffset.doubleValue, range: 16...64, step: 1, suffix: "px")
            }

            SettingsGroup("响应时间") {
                SliderSetting(title: "进入延迟", value: $settings.hoverEnterDelay, range: 0...0.35, step: 0.01, suffix: "s", decimals: 2)
                SliderSetting(title: "隐藏延迟", value: $settings.hideDelay, range: 0...0.6, step: 0.01, suffix: "s", decimals: 2)
            }
        }
    }

    private var animationPane: some View {
        SettingsPage(title: "动画", subtitle: "调整展开、收起和内容淡入淡出的节奏。") {
            SettingsGroup("时长") {
                SliderSetting(title: "展开时长", value: $settings.expandDuration, range: 0.2...1.2, step: 0.01, suffix: "s", decimals: 2)
                SliderSetting(title: "收起时长", value: $settings.collapseDuration, range: 0.12...0.7, step: 0.01, suffix: "s", decimals: 2)
                SliderSetting(title: "内容出现延迟", value: $settings.revealDelay, range: 0...0.5, step: 0.01, suffix: "s", decimals: 2)
                SliderSetting(title: "内容淡入", value: $settings.contentFadeInDuration, range: 0.05...0.4, step: 0.01, suffix: "s", decimals: 2)
                SliderSetting(title: "内容淡出", value: $settings.contentFadeOutDuration, range: 0.03...0.25, step: 0.01, suffix: "s", decimals: 2)
            }

            SettingsGroup("时间曲线") {
                TextFieldSetting(title: "展开曲线", text: $settings.expandTimingCurve)
                TextFieldSetting(title: "收起曲线", text: $settings.collapseTimingCurve)
            }
        }
    }
}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case overview
    case appearance
    case trigger
    case animation

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "基础设置"
        case .appearance: "外观布局"
        case .trigger: "触发方式"
        case .animation: "动画"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gearshape"
        case .appearance: "paintbrush"
        case .trigger: "cursorarrow"
        case .animation: "timelapse"
        }
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 28, weight: .semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            content
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            VStack(spacing: 12) {
                content
            }
            .padding(14)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.separator.opacity(0.35))
            }
        }
    }
}

private struct MetricTile: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.separator.opacity(0.35))
        }
    }
}

private struct SliderSetting: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let suffix: String
    let decimals: Int

    init(title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, suffix: String, decimals: Int = 0) {
        self.title = title
        self._value = value
        self.range = range
        self.step = step
        self.suffix = suffix
        self.decimals = decimals
    }

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .frame(width: 118, alignment: .leading)

            Slider(value: $value, in: range, step: step)

            Text(formattedValue)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
    }

    private var formattedValue: String {
        let number = String(format: "%.\(decimals)f", value)
        return suffix.isEmpty ? number : "\(number) \(suffix)"
    }
}

private struct StepperSetting: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let suffix: String

    var body: some View {
        Stepper(value: $value, in: range) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value) \(suffix)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct TextFieldSetting: View {
    let title: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .frame(width: 118, alignment: .leading)
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
        }
    }
}

private struct EmptyState: View {
    let title: String
    let symbol: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(title)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

private struct AppTile: View {
    let app: AppItem
    let isDragging: Bool
    let onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 8) {
                appIcon
                    .frame(width: 56, height: 56)

                Text(app.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .frame(minHeight: 92)
            .frame(maxWidth: .infinity)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("移除")
            .padding(5)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isDragging ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor).opacity(0.72))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isDragging ? Color.accentColor.opacity(0.55) : Color(nsColor: .separatorColor).opacity(0.28))
        }
        .opacity(isDragging ? 0.68 : 1)
    }

    @ViewBuilder
    private var appIcon: some View {
        if let path = app.path {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "app")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }
}

private struct AppTileDropDelegate: DropDelegate {
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

private extension Binding where Value == CGFloat {
    var doubleValue: Binding<Double> {
        Binding<Double>(
            get: { Double(wrappedValue) },
            set: { wrappedValue = CGFloat($0) }
        )
    }
}
