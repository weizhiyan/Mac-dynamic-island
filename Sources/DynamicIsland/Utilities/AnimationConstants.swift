import SwiftUI

// 所有动画/布局参数已迁移到 SettingsStore，可在设置面板中调整。
// 此文件仅保留 AppIconView 依赖的 .islandReveal 动画扩展。

extension Animation {
    static var islandReveal: Animation { .spring(response: 0.24, dampingFraction: 0.96) }
}
