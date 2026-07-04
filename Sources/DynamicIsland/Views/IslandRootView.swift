import SwiftUI

struct IslandRootView: View {
    @EnvironmentObject var appStore: AppStore
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var viewModel: IslandViewModel

    var body: some View {
        AppGrid()
            .padding(.top, settings.contentTopPadding)
            .padding(.horizontal, settings.contentPadding)
            .padding(.bottom, settings.contentPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
