import JibunKitCore
import SwiftUI
import WidgetKit
import WidgetFeatureA
import WidgetFeatureB

@main
struct WidgetFixtureHostApp: App {
    @State private var status: String
    private let management: MiniAppManagement
    private let owners: Set<String>

    init() {
        let configured = Set((Bundle.main.object(forInfoDictionaryKey: "WidgetFixtureOwners") as? String ?? "")
            .split(separator: ",").map(String.init))
        owners = configured
        let definitions = Self.definitions(for: configured)
        let defaults = (try? MiniAppStorage.sharedDefaults()) ?? .standard
        management = MiniAppManagement(
            registrations: definitions.map { definition in
                .init(
                    id: definition.id,
                    lifetime: definition.lifetime,
                    removal: definition.removal,
                    unregister: { try await definition.onUnregister?() }
                )
            },
            defaults: defaults,
            consents: MiniAppConsentStore(defaults: defaults),
            coordinator: .shared,
            onStatusChange: { _, _ in WidgetCenter.shared.reloadAllTimelines() }
        )
        _status = State(initialValue: "initializing")
    }

    var body: some Scene {
        WindowGroup {
            VStack {
                Text(status).accessibilityIdentifier("widget-fixture.status")
                Button("Update Feature A") {
                    perform("a-updated") { try await Self.write(owner: FeatureAStore.id, value: 33) }
                }
                .accessibilityIdentifier("widget-fixture.update-a")
                Button("Disable Feature A") {
                    perform("a-disabled") { try await management.disable(FeatureAStore.id) }
                }
                .accessibilityIdentifier("widget-fixture.disable-a")
                Button("Enable Feature A") {
                    perform("a-enabled") { try await management.enable(FeatureAStore.id) }
                }
                .accessibilityIdentifier("widget-fixture.enable-a")
                Button("Delete Feature A") {
                    perform("a-deleted") { try await management.remove(FeatureAStore.id) }
                }
                .accessibilityIdentifier("widget-fixture.delete-a")
                Button("Re-register Feature A") {
                    perform("a-reregistered") {
                        try await management.enable(FeatureAStore.id)
                        try await Self.write(owner: FeatureAStore.id, value: 44)
                    }
                }
                .accessibilityIdentifier("widget-fixture.reregister-a")
            }
            .task { await initialize() }
        }
    }

    @MainActor
    private func initialize() async {
        do {
            if owners.contains("A") { try await Self.write(owner: FeatureAStore.id, value: 11) }
            if owners.contains("B") { try await Self.write(owner: FeatureBStore.id, value: 22) }
            WidgetCenter.shared.reloadAllTimelines()
            status = "ready"
        } catch {
            fail(error)
        }
    }

    @MainActor
    private func perform(_ success: String, operation: @escaping @MainActor () async throws -> Void) {
        Task {
            do {
                try await operation()
                WidgetCenter.shared.reloadAllTimelines()
                status = success
            } catch { fail(error) }
        }
    }

    @MainActor
    private func fail(_ error: Error) {
        status = "storage-error:\(error)"
        print(status)
    }

    private static func write(owner: MiniAppID, value: Int) async throws {
        let defaults = try MiniAppStorage.sharedDefaults()
        try await MiniAppRestoreCoordinator.shared.withStoreAccess(for: owner) {
            MiniAppStorage.withExclusiveAccess {
                defaults.set(value, forKey: MiniAppContext(id: owner).storageKey("shared-value"))
            }
        }
    }

    @MainActor
    private static func definitions(for owners: Set<String>) -> [MiniAppDefinition] {
        var result: [MiniAppDefinition] = []
        if owners.contains("A") { result.append(FeatureAMiniApp.definition) }
        if owners.contains("B") { result.append(FeatureBMiniApp.definition) }
        return result
    }
}
