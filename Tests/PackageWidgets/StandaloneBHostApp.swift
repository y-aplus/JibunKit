import JibunKitCore
import SwiftUI
import WidgetFeatureB
import WidgetKit

@main
struct StandaloneBHostApp: App {
    @State private var status = "initializing"
    var body: some Scene {
        WindowGroup {
            Text(status).accessibilityIdentifier("widget-fixture.status").task {
                do {
                    let defaults = try MiniAppStorage.sharedDefaults()
                    let store = FeatureBStore(defaults: defaults)
                    let definition = FeatureBMiniApp.definition(store: store)
                    let management = MiniAppManagement(
                        registrations: [.init(id: definition.id, lifetime: definition.lifetime,
                                              removal: definition.removal)],
                        defaults: defaults, consents: .init(defaults: defaults), coordinator: .shared)
                    if management.isEnabled(FeatureBStore.id) {
                        try await MiniAppRestoreCoordinator.shared.withStoreAccess(for: FeatureBStore.id) {
                            try store.seedIfMissing(22)
                        }
                    }
                    WidgetCenter.shared.reloadAllTimelines()
                    status = "ready"
                } catch { status = "shared-store-unavailable:\(error)" }
            }
        }
    }
}
