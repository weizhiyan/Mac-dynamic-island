import SwiftUI
import AppKit

struct AppIconView: View {
    let item: AppItem
    let size: CGFloat
    var reveal: Bool

    @State private var hovered = false

    var body: some View {
        Image(nsImage: IconLoader.icon(for: item))
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.30, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                    .stroke(Color.white.opacity(hovered ? 0.28 : 0.08), lineWidth: 1)
            }
            .scaleEffect(hovered ? 1.08 : 1.0)
            .shadow(color: .black.opacity(0.30), radius: 8, y: 4)
            .opacity(reveal ? 1 : 0)
            .offset(y: reveal ? 0 : 12)
            .animation(.islandReveal, value: reveal)
            .onHover { hovered = $0 }
            .onTapGesture { AppLauncher.launch(item) }
    }
}
