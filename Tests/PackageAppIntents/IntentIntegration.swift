import IntentFeatureA
import IntentFeatureB
import JibunKitCore
import SwiftUI

extension MiniAppID {
    static let intentFixtureA = MiniAppID("intent-fixture-a")
    static let intentFixtureB = MiniAppID("intent-fixture-b")
}

struct FeatureABoundary: IntentFeatureA.StoreOperationBoundary {
    func perform<Value: Sendable>(
        _ operation: @escaping @MainActor @Sendable () throws -> Value
    ) async throws -> Value {
        try await MiniAppRestoreCoordinator.shared.withStoreAccess(for: .intentFixtureA) {
            try await operation()
        }
    }
}

struct FeatureBBoundary: IntentFeatureB.StoreOperationBoundary {
    func perform<Value: Sendable>(
        _ operation: @escaping @MainActor @Sendable () throws -> Value
    ) async throws -> Value {
        try await MiniAppRestoreCoordinator.shared.withStoreAccess(for: .intentFixtureB) {
            try await operation()
        }
    }
}

@MainActor
enum IntentFixtureIntegration {
    static let defaults = UserDefaults(suiteName: "com.jibunkit.intent-fixture.management")!
    static let consents = MiniAppConsentStore(defaults: defaults)

    static let definitionA = MiniAppDefinition(
        id: .intentFixtureA, title: "Intent Feature A", systemImage: "a.circle",
        removal: MiniAppRemovalProvider(id: .intentFixtureA, dataDescription: "Feature A values") {
            await IntentFeatureA.FeatureAStore.shared.removeAllReserved()
        }
    ) { _ in Text("Intent Feature A") }

    static let definitionB = MiniAppDefinition(
        id: .intentFixtureB, title: "Intent Feature B", systemImage: "b.circle",
        removal: MiniAppRemovalProvider(id: .intentFixtureB, dataDescription: "Feature B values") {
            await IntentFeatureB.FeatureBStore.shared.removeAllReserved()
        }
    ) { _ in Text("Intent Feature B") }

    static var management: MiniAppManagement = makeManagement()

    static func resetManagement() {
        management = makeManagement()
        IntentFeatureA.FeatureAStore.shared.configure(boundary: FeatureABoundary())
        IntentFeatureB.FeatureBStore.shared.configure(boundary: FeatureBBoundary())
    }

    private static func makeManagement() -> MiniAppManagement {
        MiniAppManagement(registrations: [
            .init(id: definitionA.id, removal: definitionA.removal),
            .init(id: definitionB.id, removal: definitionB.removal),
        ], defaults: defaults, consents: consents)
    }
}
