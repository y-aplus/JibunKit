import JibunKitCore
import SwiftUI
import WidgetFeatureA
import WidgetKit

@main
struct StandaloneAHostApp: App {
    @State private var status = "initializing"
    var body: some Scene {
        WindowGroup {
            Text(status).accessibilityIdentifier("widget-fixture.status").task {
                do {
                    let defaults = try MiniAppStorage.sharedDefaults()
                    let store = FeatureAStore(defaults: defaults)
                    let definition = FeatureAMiniApp.definition(store: store)
                    let management = MiniAppManagement(
                        registrations: [.init(id: definition.id, lifetime: definition.lifetime,
                                              removal: definition.removal)],
                        defaults: defaults, consents: .init(defaults: defaults), coordinator: .shared)
                    if management.isEnabled(FeatureAStore.id) {
                        try await MiniAppRestoreCoordinator.shared.withStoreAccess(for: FeatureAStore.id) {
                            try store.seedIfMissing(11)
                        }
                    }
                    WidgetCenter.shared.reloadAllTimelines()
                    status = "ready"
                } catch { status = "shared-store-unavailable:\(error)" }
            }
        }
    }
}
