import JibunKitCore
import SwiftUI
import WidgetFeatureA
import WidgetFeatureB
import WidgetKit

@main
struct WidgetFixtureHostApp: App {
    private struct Configuration: Sendable {
        let aStore: FeatureAStore
        let bStore: FeatureBStore
        let management: MiniAppManagement

        @MainActor static func make() throws -> Self {
            let defaults = try MiniAppStorage.sharedDefaults()
            let aStore = FeatureAStore(defaults: defaults)
            let bStore = FeatureBStore(defaults: defaults)
            let definitions = [FeatureAMiniApp.definition(store: aStore), FeatureBMiniApp.definition(store: bStore)]
            let management = MiniAppManagement(
                registrations: definitions.map { definition in
                    .init(id: definition.id, lifetime: definition.lifetime, removal: definition.removal,
                          unregister: { try await definition.onUnregister?() })
                }, defaults: defaults, consents: .init(defaults: defaults), coordinator: .shared,
                onStatusChange: { _, _ in WidgetCenter.shared.reloadAllTimelines() })
            return Self(aStore: aStore, bStore: bStore, management: management)
        }
    }

    @State private var status: String
    private let configuration: Configuration?

    init() {
        do {
            configuration = try Configuration.make()
            _status = State(initialValue: "initializing")
        } catch {
            configuration = nil
            _status = State(initialValue: "shared-store-unavailable:\(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            VStack {
                Text(status).accessibilityIdentifier("widget-fixture.status")
                Button("Update Feature A") { writeA(33, success: "a-updated") }
                    .accessibilityIdentifier("widget-fixture.update-a")
                Button("Disable Feature A") {
                    perform("a-disabled") {
                        guard let configuration else { throw FeatureAStoreError.sharedStoreUnavailable }
                        try await configuration.management.disable(FeatureAStore.id)
                    }
                }.accessibilityIdentifier("widget-fixture.disable-a")
                Button("Enable Feature A") {
                    perform("a-enabled") {
                        guard let configuration else { throw FeatureAStoreError.sharedStoreUnavailable }
                        try await configuration.management.enable(FeatureAStore.id)
                    }
                }.accessibilityIdentifier("widget-fixture.enable-a")
                Button("Delete Feature A") {
                    perform("a-deleted") {
                        guard let configuration else { throw FeatureAStoreError.sharedStoreUnavailable }
                        try await configuration.management.remove(FeatureAStore.id)
                    }
                }.accessibilityIdentifier("widget-fixture.delete-a")
                Button("Re-register Feature A") {
                    perform("a-reregistered") {
                        guard let configuration else { throw FeatureAStoreError.sharedStoreUnavailable }
                        try await configuration.management.enable(FeatureAStore.id)
                    }
                }.accessibilityIdentifier("widget-fixture.reregister-a")
                Button("Write New Feature A") { writeA(44, success: "a-recreated") }
                    .accessibilityIdentifier("widget-fixture.recreate-a")
            }
            .task { await seedNewInstallationValues() }
        }
    }

    @MainActor private func seedNewInstallationValues() async {
        guard let configuration else { return }
        do {
            if configuration.management.isEnabled(FeatureAStore.id) {
                try await MiniAppRestoreCoordinator.shared.withStoreAccess(for: FeatureAStore.id) {
                    try configuration.aStore.seedIfMissing(11)
                }
            }
            if configuration.management.isEnabled(FeatureBStore.id) {
                try await MiniAppRestoreCoordinator.shared.withStoreAccess(for: FeatureBStore.id) {
                    try configuration.bStore.seedIfMissing(22)
                }
            }
            WidgetCenter.shared.reloadAllTimelines()
            status = "ready"
        } catch { fail(error) }
    }

    @MainActor private func writeA(_ value: Int, success: String) {
        perform(success) {
            guard let configuration else { throw FeatureAStoreError.sharedStoreUnavailable }
            try await FeatureAAccess(store: configuration.aStore).set(value)
        }
    }

    @MainActor private func perform(_ success: String, operation: @escaping @MainActor () async throws -> Void) {
        Task {
            do {
                try await operation()
                WidgetCenter.shared.reloadAllTimelines()
                status = success
            } catch { fail(error) }
        }
    }

    @MainActor private func fail(_ error: Error) {
        status = "operation-error:\(error)"
        print(status)
    }
}
