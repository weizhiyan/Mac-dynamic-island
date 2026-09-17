import SwiftUI
import AppKit

/// 菜单栏气泡弹窗：上栏「已收纳」= 当前被挤出可见菜单栏的图标，下栏「菜单栏」= 可见图标镜像。
/// 两栏都直接来自实时 AX 判定，应用一退出条目就消失，无需任何本地名单。
struct MenuBarPopoverView: View {
    @ObservedObject private var iconManager = MenuBarIconManager.shared

    var isIslandEnabled: Bool
    var onToggleIsland: () -> Void
    var onSettings: () -> Void
    var onCheckUpdates: () -> Void
    var onQuit: () -> Void

    private let columns = 4
    private let iconSize: CGFloat = 32
    private let spacing: CGFloat = 8
    private let cellPadding: CGFloat = 10
    /// 格子比图标大一圈，给右上角的角标留位置，避免角标被相邻格子裁掉
    private var cellSize: CGFloat { iconSize + 6 }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !iconManager.accessibilityGranted {
                accessibilityBanner
                Divider()
            }
            if let message = iconManager.lastMoveMessage {
                moveErrorHint(message)
                Divider()
            }
            if iconManager.isArranging {
                arrangeHint
                Divider()
            }
            grid(iconManager.stashedIcons(), badge: .unstash,
                 emptyHint: "还没有收纳任何图标，点下方图标右上角的 ＋")
            Divider()
            mirrorHeader
            grid(iconManager.visibleIcons(), badge: .stash,
                 emptyHint: "没有检测到菜单栏图标")
            Divider()
            actionBar
        }
        .frame(width: popoverWidth)
        .fixedSize()
    }

    private var popoverWidth: CGFloat {
        CGFloat(columns) * cellSize + CGFloat(columns - 1) * spacing + cellPadding * 2
    }

    // MARK: - 标题栏

    private var header: some View {
        HStack(spacing: 4) {
            Text("已收纳")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Spacer(minLength: 0)
            Button {
                if iconManager.isArranging {
                    iconManager.endArrange()
                } else {
                    iconManager.beginArrange()
                }
            } label: {
                Image(systemName: iconManager.isArranging
                      ? "checkmark.circle" : "arrow.left.arrow.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(iconManager.isArranging ? .accentColor : .secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!iconManager.accessibilityGranted)
            .help(iconManager.isArranging ? "完成整理" : "整理：手动按住 ⌘ 拖动图标（角标失效时用）")
        }
        .padding(.horizontal, cellPadding)
        .padding(.vertical, 8)
    }

    private var mirrorHeader: some View {
        HStack {
            Text("菜单栏图标")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            Text("点 ＋ 收纳")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, cellPadding)
        .padding(.top, 6)
    }
    // MARK: - 提示条

    /// 辅助功能权限缺失：AX 枚举拿不到任何图标，功能整体不可用
    private var accessibilityBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundColor(.orange)
            Text("需要「辅助功能」权限才能识别菜单栏图标")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("去开启") { iconManager.requestAccessibilityPermission() }
                .font(.system(size: 10))
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, cellPadding)
        .padding(.vertical, 6)
    }

    /// 角标移动失败：合成拖拽被目标应用拒绝，指路手动整理
    private func moveErrorHint(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(.orange)
            Text(message)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, cellPadding)
        .padding(.vertical, 6)
    }

    /// 整理模式：角标失效时的手动兜底
    private var arrangeHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.draw")
                .font(.system(size: 10))
                .foregroundColor(.accentColor)
            Text("按住 ⌘ 拖动菜单栏图标，越过 ‹ 分隔符即收纳，拖回右侧即取消。"
                 + "\(Int(iconManager.arrangeDuration)) 秒后自动恢复")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, cellPadding)
        .padding(.vertical, 6)
    }

    // MARK: - 图标网格

    private func grid(
        _ icons: [MenuBarIconInfo], badge: MenuBarIconBadge, emptyHint: String
    ) -> some View {
        let rows = max(1, Int(ceil(Double(icons.count) / Double(columns))))
        return VStack(spacing: spacing) {
            if icons.isEmpty {
                Text(emptyHint)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .frame(height: cellSize)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = row * columns + column
                            if index < icons.count {
                                MenuBarIconCell(
                                    info: icons[index],
                                    iconSize: iconSize,
                                    cellSize: cellSize,
                                    badge: badge,
                                    isPressing: iconManager.pressingBundleID == icons[index].bundleID,
                                    isMoving: iconManager.movingBundleID == icons[index].bundleID,
                                    badgeEnabled: iconManager.accessibilityGranted
                                        && iconManager.movingBundleID == nil
                                )
                            } else {
                                Color.clear.frame(width: cellSize, height: cellSize)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, cellPadding)
        .padding(.vertical, 4)
    }
    // MARK: - 底部操作栏

    private var actionBar: some View {
        HStack(spacing: 0) {
            actionButton(
                isIslandEnabled ? "隐藏" : "显示",
                isIslandEnabled ? "eye.slash" : "eye",
                onToggleIsland
            )
            actionButton("设置", "gearshape", onSettings)
            actionButton("更新", "arrow.triangle.2.circlepath", onCheckUpdates)
            actionButton("退出", "power", onQuit)
        }
        .padding(.vertical, 6)
    }

    private func actionButton(_ title: String, _ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 8))
            }
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 单个图标格子

/// 右上角角标要做的事：镜像区是「＋ 收纳」，已收纳区是「－ 恢复」。
enum MenuBarIconBadge {
    case stash
    case unstash

    var symbol: String { self == .stash ? "plus.circle.fill" : "minus.circle.fill" }
    var tint: Color { self == .stash ? .accentColor : .red }
    var hint: String { self == .stash ? "收纳（从菜单栏隐藏）" : "恢复到菜单栏" }
}

private struct MenuBarIconCell: View {
    let info: MenuBarIconInfo
    let iconSize: CGFloat
    let cellSize: CGFloat
    let badge: MenuBarIconBadge
    let isPressing: Bool
    let isMoving: Bool
    let badgeEnabled: Bool
    @State private var isHovered = false

    private var isBusy: Bool { isPressing || isMoving }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button {
                MenuBarIconManager.shared.clickIcon(withBundleID: info.bundleID)
            } label: {
                Image(nsImage: info.icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(3)
                    .frame(width: iconSize, height: iconSize)
                    .opacity(isBusy ? 0.35 : 1)
                    .overlay { if isBusy { ProgressView().controlSize(.small) } }
                    .scaleEffect(isHovered ? 1.08 : 1.0)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .onHover { isHovered = $0 }
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
            .frame(width: cellSize, height: cellSize, alignment: .bottomLeading)

            badgeButton
        }
        .frame(width: cellSize, height: cellSize)
        .help(info.appName)
    }

    private var badgeButton: some View {
        Button {
            switch badge {
            case .stash: MenuBarIconManager.shared.stash(bundleID: info.bundleID)
            case .unstash: MenuBarIconManager.shared.unstash(bundleID: info.bundleID)
            }
        } label: {
            Image(systemName: badge.symbol)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, badge.tint)
                // 白底描边，保证压在深色应用图标上也看得清
                .background(Circle().fill(.white).padding(1.5))
                .frame(width: 16, height: 16)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!badgeEnabled || isBusy)
        .opacity(badgeEnabled ? 1 : 0.35)
        .help(badge.hint)
    }
}
