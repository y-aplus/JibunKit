#if os(iOS)
import JibunKitCore
import Observation
import SwiftUI

struct MiniAppListScreen: View {
    @Bindable var navigation: AppNavigation

    var body: some View {
        NavigationStack(path: $navigation.path) {
            List {
                ForEach(MiniAppRegistry.all) { miniApp in
                    NavigationLink(value: miniApp.id) {
                        Label(miniApp.title, systemImage: miniApp.systemImage)
                    }
                }
            }
            .navigationTitle("ミニアプリ")
            .navigationDestination(for: MiniAppID.self) { miniAppID in
                if let miniApp = MiniAppRegistry.definition(for: miniAppID) {
                    miniApp.makeDestination()
                } else {
                    ContentUnavailableView(
                        "ミニアプリを開けません",
                        systemImage: "questionmark.app"
                    )
                }
            }
        }
    }
}
#endif
