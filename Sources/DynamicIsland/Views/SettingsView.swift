import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var appStore: AppStore
    @State private var selectedPane: SettingsPane? = .overview
    @State private var draggedApp: AppItem?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 224)

            Divider()

            ScrollView {
                paneContent
                    .frame(maxWidth: 680, alignment: .leading)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 760, minHeight: 560)
        .ignoresSafeArea(.container, edges: .top)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("灵动岛设置")
                .font(.system(size: 13, weight: .semibold))
                .padding(.leading, 50)
                .padding(.top, 30)

            VStack(spacing: 4) {
                ForEach(SettingsPane.allCases) { pane in
                    Button {
                        selectedPane = pane
                    } label: {
                        Label(pane.title, systemImage: pane.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(SettingsSidebarButtonStyle(isSelected: selectedPane == pane))
                }
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.9))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.38))
        }
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        .padding(.leading, 12)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var paneContent: some View {
        switch selectedPane ?? .overview {
        case .overview:
            overviewPane
        case .appearance:
            appearancePane
        case .animation:
            animationPane
        case .trigger:
            triggerPane
        }
    }

    private var overviewPane: some View {
        SettingsPage(title: "基础设置") {
            appManagementSection

            HStack(spacing: 12) {
                MetricTile(title: "快捷应用", value: "\(appStore.apps.count)", symbol: "app")
                MetricTile(title: "展开尺寸", value: "\(Int(settings.expandedWidth)) x \(Int(settings.expandedHeight))", symbol: "arrow.up.left.and.arrow.down.right")
                MetricTile(title: "触发区", value: "\(Int(settings.hoverZoneWidth)) x \(Int(settings.hoverZoneHeight))", symbol: "cursorarrow")
            }

            SettingsGroup("自定义布局") {
                HStack {
                    Label("组件化自定义面板", systemImage: "slider.horizontal.3")
                    Spacer()
                    Button("打开面板") {
                        AppDelegate.shared?.openCustomizePanel()
                    }
                }
                Text("把音乐摘要、指标、时钟、电池等组件拖进灵动岛的不同槽位；尺寸、收起带、动画按类型分成 Tab，边调边看屏幕上方真实效果。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsGroup("系统") {
                Toggle(isOn: $settings.launchAtLoginEnabled) {
                    Label("开机自启动", systemImage: "power")
                }
            }

            SettingsGroup("音乐播放") {
                HStack {
                    Label("绑定播放器", systemImage: "music.note")
                    Spacer()
                    Picker("绑定播放器", selection: $settings.mediaPlayerBundleID) {
                        Text("不显示").tag(String?.none)
                        ForEach(MediaPlayerOption.allCases.filter(\.isInstalled)) { option in
                            Text(option.title).tag(Optional(option.rawValue))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                Text("还没绑定播放器时，点灵动岛上的播放会自动打开已安装的播放器并开始播放，之后想换播放器在这里改。播放控制需要允许灵动岛自动化操作所选播放器。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsGroup("更新") {
                HStack {
                    Label("当前版本 \(appVersion)", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    Button("检查更新") {
                        AppDelegate.shared?.checkForUpdates()
                    }
                }
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

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        if let version, let build, !build.isEmpty {
            return "\(version) (\(build))"
        }

        return version ?? "未知"
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
                        AppTile(app: app) {
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
        SettingsPage(title: "外观布局") {
            SettingsGroup("岛屿形状") {
                NumericSetting(title: "收缩宽度", value: $settings.compactWidth.doubleValue, range: 90...240, suffix: "px")
                NumericSetting(title: "收缩高度", value: $settings.compactHeight.doubleValue, range: 1...10, suffix: "px")
                NumericSetting(title: "顶部融合高度", value: $settings.topBarHeight.doubleValue, range: 27...70, suffix: "px")
                NumericSetting(title: "整体上移", value: $settings.topBarYOffset.doubleValue, range: 18...64, suffix: "px")
            }

            SettingsGroup("圆角") {
                NumericSetting(title: "收起态", value: $settings.compactCornerRadius.doubleValue, range: 0...40, suffix: "pt")
                NumericSetting(title: "展开态", value: $settings.expandedCornerRadius.doubleValue, range: 0...40, suffix: "pt")
                Text("收起态圆角只在刘海带露出时可见；展开态圆角同时作用于自定义面板的预览。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsGroup("收起音乐层") {
                Toggle(isOn: $settings.compactBandAutoSize) {
                    Label("自动匹配刘海尺寸", systemImage: "wand.and.rays")
                }

                if !settings.compactBandAutoSize {
                    NumericSetting(title: "总宽度", value: $settings.compactBandWidth.doubleValue, range: 80...900, suffix: "pt")
                    NumericSetting(title: "总高度", value: $settings.compactBandHeight.doubleValue, range: 20...80, suffix: "pt")
                }

                NumericSetting(title: "顶部过渡圆角", value: $settings.compactBandTopRadius.doubleValue, range: 0...40, suffix: "pt")
                NumericSetting(title: "底部圆角", value: $settings.compactBandBottomRadius.doubleValue, range: 0...40, suffix: "pt")
                NumericSetting(title: "垂直偏移", value: $settings.compactBandYOffset.doubleValue, range: -20...20, suffix: "pt")
                Text("圆角填 0 使用自动值；手动尺寸只在关闭自动匹配后生效。应用网格的图标大小、列数、间距请在「自定义布局」面板里调。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsGroup("维护") {
                HStack {
                    Label("恢复外观布局默认值", systemImage: "arrow.counterclockwise")
                    Spacer()
                    Button("恢复默认") {
                        settings.restoreLayoutDefaults()
                    }
                }
            }
        }
    }

    private var triggerPane: some View {
        SettingsPage(title: "触发方式") {
            SettingsGroup("触发区域") {
                HStack {
                    Label("显示当前触发区域", systemImage: "eye")
                    Spacer()
                    Button("显示触发区域") {
                        AppDelegate.shared?.showTriggerAreaPreview()
                    }
                }
                NumericSetting(title: "区域宽度", value: $settings.hoverZoneWidth.doubleValue, range: 120...360, suffix: "px")
                NumericSetting(title: "区域高度", value: $settings.hoverZoneHeight.doubleValue, range: 3...24, suffix: "px")
                NumericSetting(title: "纵向偏移", value: $settings.hoverZoneYOffset.doubleValue, range: 16...64, suffix: "px")
            }

            SettingsGroup("响应时间") {
                SliderSetting(title: "进入延迟", value: $settings.hoverEnterDelay, range: 0...0.35, step: 0.01, suffix: "s", decimals: 2)
                SliderSetting(title: "隐藏延迟", value: $settings.hideDelay, range: 0...0.6, step: 0.01, suffix: "s", decimals: 2)
            }
        }
    }

    private var animationPane: some View {
        SettingsPage(title: "动画") {
            SettingsGroup("展开与收起") {
                AnimationTimingSetting(
                    title: "展开",
                    symbol: "arrow.down.right.and.arrow.up.left",
                    duration: $settings.expandDuration,
                    curve: $settings.expandTimingCurve,
                    fallbackCurve: "0.65, 0, 0.35, 1"
                )

                Divider()

                AnimationTimingSetting(
                    title: "收起",
                    symbol: "arrow.up.left.and.arrow.down.right",
                    duration: $settings.collapseDuration,
                    curve: $settings.collapseTimingCurve,
                    fallbackCurve: "0.25, 0.1, 0.25, 1"
                )
            }

            SettingsGroup("内容显示") {
                SliderSetting(title: "淡入延迟", value: $settings.revealDelay, range: 0...0.8, step: 0.01, suffix: "s", decimals: 2)
                SliderSetting(title: "淡入时长", value: $settings.contentFadeInDuration, range: 0...0.8, step: 0.01, suffix: "s", decimals: 2)
                SliderSetting(title: "淡出时长", value: $settings.contentFadeOutDuration, range: 0...0.5, step: 0.01, suffix: "s", decimals: 2)
            }

            SettingsGroup("试一下") {
                HStack {
                    Label("播放一遍展开与收起", systemImage: "play.rectangle")
                    Spacer()
                    Button("播放") {
                        AppDelegate.shared?.testIslandAnimation()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Text("不用把鼠标吊在刘海上，直接看完整动画效果。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsGroup("维护") {
                HStack {
                    Label("恢复动画默认值", systemImage: "arrow.counterclockwise")
                    Spacer()
                    Button("恢复默认") {
                        settings.restoreAnimationDefaults()
                    }
                }
            }
        }
    }

}

private enum SettingsPane: String, CaseIterable, Identifiable {
    case overview
    case appearance
    case animation
    case trigger

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "基础设置"
        case .appearance: "外观布局"
        case .animation: "动画"
        case .trigger: "触发方式"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gearshape"
        case .appearance: "paintbrush"
        case .animation: "timer"
        case .trigger: "cursorarrow"
        }
    }
}

private struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(title)
                .font(.system(size: 28, weight: .semibold))
            content
        }
    }
}

private struct SettingsSidebarButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : .clear)
            )
            .opacity(configuration.isPressed ? 0.72 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
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

private struct AnimationTimingSetting: View {
    let title: String
    let symbol: String
    @Binding var duration: TimeInterval
    @Binding var curve: String
    let fallbackCurve: String

    private var parsedCurve: BezierControlPoints {
        BezierControlPoints(curve) ?? BezierControlPoints(fallbackCurve)!
    }

    private var isCurveValid: Bool {
        BezierControlPoints(curve) != nil
    }

    var body: some View {
        HStack(alignment: .center, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: symbol)
                    .font(.system(size: 13, weight: .semibold))

                HStack(spacing: 12) {
                    Text("时长")
                        .frame(width: 52, alignment: .leading)
                    Slider(value: $duration, in: 0.1...1.5, step: 0.01)
                    Text(String(format: "%.2f s", duration))
                        .font(.system(.body, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 62, alignment: .trailing)
                }

                HStack(spacing: 12) {
                    Text("贝塞尔")
                        .frame(width: 52, alignment: .leading)
                    TextField("x1, y1, x2, y2", text: $curve)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .accessibilityLabel("\(title)贝塞尔曲线")
                }

                if !isCurveValid {
                    Text("请输入 4 个数值，x1 和 x2 需在 0...1 之间")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            BezierCurvePreview(points: parsedCurve)
                .frame(width: 112, height: 68)
        }
        .padding(.vertical, 2)
    }
}

private struct BezierCurvePreview: View {
    let points: BezierControlPoints

    var body: some View {
        Canvas { context, size in
            let inset: CGFloat = 6
            let width = max(1, size.width - inset * 2)
            let height = max(1, size.height - inset * 2)

            var guides = Path()
            for fraction in [0.25, 0.5, 0.75] as [CGFloat] {
                guides.move(to: CGPoint(x: inset, y: inset + height * fraction))
                guides.addLine(to: CGPoint(x: inset + width, y: inset + height * fraction))
                guides.move(to: CGPoint(x: inset + width * fraction, y: inset))
                guides.addLine(to: CGPoint(x: inset + width * fraction, y: inset + height))
            }
            context.stroke(guides, with: .color(.secondary.opacity(0.18)), lineWidth: 0.5)

            let start = CGPoint(x: inset, y: inset + height)
            let end = CGPoint(x: inset + width, y: inset)
            let control1 = CGPoint(x: inset + width * points.x1, y: inset + height * (1 - points.y1))
            let control2 = CGPoint(x: inset + width * points.x2, y: inset + height * (1 - points.y2))

            var curve = Path()
            curve.move(to: start)
            curve.addCurve(to: end, control1: control1, control2: control2)
            context.stroke(curve, with: .color(.accentColor), lineWidth: 2)

            let dotSize: CGFloat = 4
            context.fill(Path(ellipseIn: CGRect(x: control1.x - dotSize / 2, y: control1.y - dotSize / 2, width: dotSize, height: dotSize)), with: .color(.secondary))
            context.fill(Path(ellipseIn: CGRect(x: control2.x - dotSize / 2, y: control2.y - dotSize / 2, width: dotSize, height: dotSize)), with: .color(.secondary))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("贝塞尔曲线预览")
    }
}

private struct BezierControlPoints {
    let x1: CGFloat
    let y1: CGFloat
    let x2: CGFloat
    let y2: CGFloat

    init?(_ value: String) {
        let values = value
            .split(separator: ",", omittingEmptySubsequences: false)
            .compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard values.count == 4, (0...1).contains(values[0]), (0...1).contains(values[2]) else { return nil }
        x1 = CGFloat(values[0])
        y1 = CGFloat(values[1])
        x2 = CGFloat(values[2])
        y2 = CGFloat(values[3])
    }
}

private struct NumericSetting: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let suffix: String

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .frame(width: 118, alignment: .leading)

            Slider(value: $value, in: range, step: 1)

            TextField("", value: $value, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 64)
                .onChange(of: value) { _, newValue in
                    value = min(max(newValue, range.lowerBound), range.upperBound)
                }

            Text(suffix)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)
        }
    }
}

private struct StepperSetting: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let suffix: String

    var body: some View {
        HStack(spacing: 14) {
            Text(title)
                .frame(width: 118, alignment: .leading)
            Spacer(minLength: 0)
            Stepper("\(value) \(suffix)", value: $value, in: range)
                .font(.system(.body, design: .monospaced))
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
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.28))
        }
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
