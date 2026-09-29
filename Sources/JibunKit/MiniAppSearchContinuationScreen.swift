#if os(iOS)
import JibunKitCore
import SwiftUI

/// Lists the enabled Features that accepted a Spotlight "Search in App" query.
/// The chosen Feature receives the query through its own destination.
struct MiniAppSearchContinuationScreen: View {
    let navigation: AppNavigation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(navigation.searchContinuation?.routes ?? [], id: \.id) { route in
                if let miniApp = MiniAppRegistry.definition(for: route.id) {
                    Button { navigation.chooseSearchRoute(route) } label: {
                        Label(miniApp.title, systemImage: miniApp.systemImage)
                    }
                    .accessibilityIdentifier("search-continuation.\(route.id.rawValue)")
                }
            }
            .navigationTitle("「\(navigation.searchContinuation?.query ?? "")」を検索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
    }
}
#endif
