import SwiftUI
import AppKit
import ApplicationServices
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var appStore: AppStore
    @State private var selectedPane: SettingsPane = .overview
    @State private var draggedApp: AppItem?
    @State private var confirmsReset = false
    @ObservedObject private var accessibility = AccessibilityPermission.shared
    @ObservedObject private var mediaPlayer = MediaPlayerStore.shared

    init(initialPane: SettingsPane = .overview, accessibility: AccessibilityPermission = .shared) {
        _selectedPane = State(initialValue: initialPane)
        _accessibility = ObservedObject(wrappedValue: accessibility)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 184)
            Divider()
            ScrollView {
                paneContent
                    .frame(maxWidth: 680, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.top, 48)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 760, minHeight: 560)
        .ignoresSafeArea(.container, edges: .top)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibility.refresh()
        }
        .onAppear { accessibility.refresh() }
        .alert("恢复所有参数？", isPresented: $confirmsReset) {
            Button("取消", role: .cancel) {}
            Button("恢复默认", role: .destructive) { settings.restoreDefaults() }
        } message: {
            Text("布局、播放器绑定和动画参数将恢复默认值。")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("灵动岛设置")
                .font(.system(size: 13, weight: .semibold))
                .padding(.leading, 12)
                .padding(.top, 48)
            VStack(spacing: 4) {
                ForEach(SettingsPane.allCases) { pane in
                    Button { selectedPane = pane } label: {
                        Label(pane.title, systemImage: pane.symbol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(SettingsSidebarButtonStyle(isSelected: selectedPane == pane))
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 4) {
                Text("灵动岛 \(AppInstallation.version)")
                Label(AppInstallation.isInstalled ? "已安装，正在运行" : "正在运行开发副本", systemImage: "checkmark.circle")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(12)
        }
        .padding(.horizontal, 12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    @ViewBuilder
    private var paneContent: some View {
        switch selectedPane {
        case .overview: overviewPane
        case .music: musicPane
        case .apps: SettingsPage(title: "快捷应用") { appManagementSection }
        case .appearance: appearancePane
        case .animation: animationPane
        case .trigger: triggerPane
        case .about: aboutPane
        }
    }

    private var overviewPane: some View {
        SettingsPage(title: "通用") {
            SettingsGroup("启动") {
                Toggle(isOn: $settings.launchAtLoginEnabled) {
                    Label("开机自启动", systemImage: "power")
                }
            }
            SettingsGroup("菜单栏") {
                Toggle(isOn: $settings.menuBarStashEnabled) {
                    Label("菜单栏图标收纳", systemImage: "tray.and.arrow.down")
                }
                HStack {
                    Label("灵动岛菜单栏入口", systemImage: "capsule.inset.filled")
                    Spacer()
                    Button("恢复图标") { AppDelegate.shared?.restoreMenuBarIcon() }
                }
            }
            SettingsGroup("灵动岛") {
                HStack {
                    Label("组件与布局", systemImage: "slider.horizontal.3")
                    Spacer()
                    Button("自定义") { AppDelegate.shared?.openCustomizePanel() }
                }
                HStack {
                    Label("系统性能", systemImage: "waveform.path.ecg")
                    Spacer()
                    Button("活动监视器", action: AppInstallation.openActivityMonitor)
                }
            }
        }
    }

    private var musicPane: some View {
        SettingsPage(title: "音乐播放") {
            SettingsGroup("播放器") {
                HStack {
                    Label("绑定播放器", systemImage: "music.note")
                    Spacer()
                    Picker("绑定播放器", selection: $settings.mediaPlayerBundleID) {
                        Text("不显示").tag(String?.none)
                        ForEach(MediaPlayerOption.allCases) { option in
                            Text(option.title + (option.isInstalled ? "" : "（未安装）"))
                                .tag(Optional(option.rawValue))
                                .disabled(!option.isInstalled)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                }
            }
            SettingsGroup("正在播放") {
                HStack(spacing: 12) {
                    Label(mediaPlayer.isBusy ? "正在连接播放器…" : mediaPlayer.primaryStatusText,
                          systemImage: mediaPlayer.lastError == nil ? "music.note" : "exclamationmark.triangle")
                        .font(.callout).lineLimit(2)
                    Spacer()
                    Button(action: mediaPlayer.togglePlayPause) {
                        Image(systemName: mediaPlayer.playbackControlSymbol)
                            .frame(width: 24, height: 24)
                    }
                    .disabled(mediaPlayer.isBusy || settings.mediaPlayerBundleID == nil)
                    .help(mediaPlayer.playbackControlTitle)
                    .accessibilityLabel(mediaPlayer.playbackControlTitle)
                    Button("歌曲详情") { MusicWindowController.shared.present() }
                }
                if let error = mediaPlayer.lastError {
                    Text(error).font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("重试连接", action: mediaPlayer.retryConnection).disabled(mediaPlayer.isBusy)
                        if mediaPlayer.permissionRequired { Button("前往授权", action: mediaPlayer.openPermissionSettings) }
                    }
                }
            }
            if mediaPlayer.selectedOption == .soda {
                SettingsGroup("辅助功能权限") {
                    HStack {
                        Label(accessibility.isGranted ? "已授权" : "当前应用未获授权",
                              systemImage: accessibility.isGranted ? "checkmark.circle" : "lock")
                        Spacer()
                        if !accessibility.isGranted {
                            Button("前往授权", action: mediaPlayer.openPermissionSettings)
                        }
                    }
                    if !accessibility.isGranted {
                        Text("尚无歌曲时，自动开始播放需要辅助功能权限。若已开启仍显示未授权，请移除旧条目，再添加下方的当前应用。")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("定位当前应用", action: AppInstallation.revealInFinder)
                            Button("重新检测") { mediaPlayer.retryConnection() }
                        }
                        Text("\(AppInstallation.version) · \(AppInstallation.path)")
                            .font(.caption).foregroundStyle(.secondary)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var aboutPane: some View {
        SettingsPage(title: "关于与更新") {
            SettingsGroup("当前运行版本") {
                HStack {
                    Label("灵动岛 \(AppInstallation.version)", systemImage: "capsule.inset.filled")
                    Spacer()
                    Button("检查更新") { AppDelegate.shared?.checkForUpdates() }
                }
                HStack {
                    Text(AppInstallation.isInstalled ? "已安装到应用程序" : "当前运行的是开发副本")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("在访达中显示", action: AppInstallation.revealInFinder)
                }
                Text(AppInstallation.path).font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            SettingsGroup("恢复默认") {
                HStack {
                    Text("布局、播放器与动画参数")
                    Spacer()
                    Button("恢复参数") { confirmsReset = true }
                }
                HStack {
                    Text("快捷应用")
                    Spacer()
                    Button("恢复应用") { appStore.restoreDefaultApps() }
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

enum SettingsPane: String, CaseIterable, Identifiable {
    case overview
    case music
    case apps
    case appearance
    case animation
    case trigger
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "通用"
        case .music: "音乐播放"
        case .apps: "快捷应用"
        case .about: "关于与更新"
        case .appearance: "外观布局"
        case .animation: "动画"
        case .trigger: "触发方式"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "gearshape"
        case .music: "music.note"
        case .apps: "square.grid.2x2"
        case .about: "info.circle"
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
                .font(.system(size: 20, weight: .semibold))
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
            .frame(height: 36)
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

            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .padding(.vertical, 12)
            Divider()
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
        let parts = value.split(separator: ",", omittingEmptySubsequences: false)
        let values = parts
            .compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard parts.count == 4, values.count == 4, values.allSatisfy(\.isFinite),
              (0...1).contains(values[0]), (0...1).contains(values[2]) else { return nil }
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
                .accessibilityLabel(title)

            TextField("", value: $value, format: .number.precision(.fractionLength(0)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 64)
                .accessibilityLabel("\(title)，\(suffix)")
                .onChange(of: value) { _, newValue in
                    value = newValue.isFinite ? min(max(newValue, range.lowerBound), range.upperBound) : range.lowerBound
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
        if app.path != nil {
            Image(nsImage: IconLoader.icon(for: app))
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
