import AppIntents
import IntentFeatureA
import IntentFeatureB
import JibunKitCore
import SwiftUI

extension MiniAppID {
    static let intentFixtureA = MiniAppID("intent-fixture-a")
    static let intentFixtureB = MiniAppID("intent-fixture-b")
}

struct FeatureABoundary: IntentFeatureA.StoreOperationBoundary {
    func perform<Value: Sendable>(_ operation: @escaping @MainActor @Sendable () async throws -> Value) async throws -> Value {
        try await MiniAppRestoreCoordinator.shared.withStoreAccess(for: .intentFixtureA) {
            try Task.checkCancellation()
            return try await operation()
        }
    }
}

struct FeatureBBoundary: IntentFeatureB.StoreOperationBoundary {
    func perform<Value: Sendable>(_ operation: @escaping @MainActor @Sendable () async throws -> Value) async throws -> Value {
        try await MiniAppRestoreCoordinator.shared.withStoreAccess(for: .intentFixtureB) {
            try Task.checkCancellation()
            return try await operation()
        }
    }
}

@MainActor
enum IntentFixtureIntegration {
    static let defaults = UserDefaults(suiteName: "com.jibunkit.intent-fixture.management")!
    static let consents = MiniAppConsentStore(defaults: defaults)
    static let definitionA = MiniAppDefinition(
        id: .intentFixtureA, title: "Intent Feature A", systemImage: "a.circle",
        removal: MiniAppRemovalProvider(id: .intentFixtureA, dataDescription: "Feature A values and entries") {
            await IntentFeatureA.FeatureAStore.shared.removeAllReserved()
        }
    ) { _ in FeatureARootView() }
    static let definitionB = MiniAppDefinition(
        id: .intentFixtureB, title: "Intent Feature B", systemImage: "b.circle",
        removal: MiniAppRemovalProvider(id: .intentFixtureB, dataDescription: "Feature B values and entries") {
            await IntentFeatureB.FeatureBStore.shared.removeAllReserved()
        }
    ) { _ in FeatureBRootView() }
    static var management: MiniAppManagement = makeManagement()

    static func bootstrap() {
        _ = management
        FeatureAStore.shared.configure(boundary: FeatureABoundary())
        FeatureBStore.shared.configure(boundary: FeatureBBoundary())
    }
    static func reconstructManagement() { management = makeManagement(); bootstrap() }
    private static func makeManagement() -> MiniAppManagement {
        MiniAppManagement(registrations: [
            .init(id: definitionA.id, removal: definitionA.removal),
            .init(id: definitionB.id, removal: definitionB.removal),
        ], defaults: defaults, consents: consents)
    }
}

@MainActor enum IntentFixtureBootstrap { static func start() { IntentFixtureIntegration.bootstrap() } }

struct IntentFixtureRootView: View {
    @State private var revision = 0
    @State private var message = "ready"
    var body: some View {
        NavigationStack {
            List {
                owner("A", id: .intentFixtureA, destination: IntentFixtureIntegration.definitionA.makeDestination())
                owner("B", id: .intentFixtureB, destination: IntentFixtureIntegration.definitionB.makeDestination())
                Text(message).accessibilityIdentifier("intent-fixture.status")
            }.navigationTitle("Intent fixture").id(revision)
        }
    }
    @ViewBuilder private func owner(_ label: String, id: MiniAppID, destination: AnyView) -> some View {
        Section("Feature \(label)") {
            Text(IntentFixtureIntegration.management.status(for: id)?.rawValue ?? "unknown")
                .accessibilityIdentifier("intent-fixture.\(label.lowercased()).management-status")
            NavigationLink("Open Feature \(label)") { destination }
            Button("Disable \(label)") { run { try await IntentFixtureIntegration.management.disable(id) } }
                .accessibilityIdentifier("intent-fixture.\(label.lowercased()).disable")
            Button("Enable \(label)") { run { try await IntentFixtureIntegration.management.enable(id) } }
                .accessibilityIdentifier("intent-fixture.\(label.lowercased()).enable")
            Button("Remove \(label)", role: .destructive) { run { try await IntentFixtureIntegration.management.remove(id) } }
                .accessibilityIdentifier("intent-fixture.\(label.lowercased()).remove")
        }
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        Task { @MainActor in
            do { try await operation(); message = "completed" } catch { message = "error: \(error)" }
            revision += 1
        }
    }
}

private struct FeatureARootView: View {
    @State private var value = 0
    @State private var title = "A candidate"
    @State private var entries: [String: String] = [:]
    @State private var message = ""
    var body: some View {
        Form {
            Text("A value: \(value)").accessibilityIdentifier("intent-fixture.a.value")
            TextField("Candidate title", text: $title)
            Button("Add A candidate") { run { var next = try await FeatureAStore.shared.entries(); next["a-candidate"] = title; try await FeatureAStore.shared.replaceEntries(next) } }
            Button("Add 1") { run { let result = try await FeatureAAddValueIntent(amount: 1).perform(); guard let saved = result.value else { throw IntentFixtureFailure.missingReturnValue }; value = saved } }
            Button("Fail next save") { FeatureAStore.shared.injectNextSaveFailure(); message = "next save will fail" }
            Button("Delay next save 5 seconds") { FeatureAStore.shared.delayNextSave(nanoseconds: 5_000_000_000); message = "next save delayed" }
            ForEach(entries.keys.sorted(), id: \.self) { key in Text("\(key): \(entries[key]!)") }
            Button("Refresh") { Task { await reload() } }
            Text(message)
        }.task { await reload() }.navigationTitle("Feature A")
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) { Task { do { try await operation(); message = "completed" } catch { message = "error: \(error)" }; await reload() } }
    private func reload() async { value = (try? await FeatureAStore.shared.value()) ?? value; entries = (try? await FeatureAStore.shared.entries()) ?? entries }
}

private struct FeatureBRootView: View {
    @State private var value = 0
    @State private var title = "B candidate"
    @State private var entries: [String: String] = [:]
    @State private var message = ""
    var body: some View {
        Form {
            Text("B value: \(value)").accessibilityIdentifier("intent-fixture.b.value")
            TextField("Candidate title", text: $title)
            Button("Add B candidate") { run { var next = try await FeatureBStore.shared.entries(); next["b-candidate"] = title; try await FeatureBStore.shared.replaceEntries(next) } }
            Button("Add 1") { run { let result = try await FeatureBAddValueIntent(amount: 1).perform(); guard let saved = result.value else { throw IntentFixtureFailure.missingReturnValue }; value = saved } }
            Button("Fail next save") { FeatureBStore.shared.injectNextSaveFailure(); message = "next save will fail" }
            Button("Delay next save 5 seconds") { FeatureBStore.shared.delayNextSave(nanoseconds: 5_000_000_000); message = "next save delayed" }
            ForEach(entries.keys.sorted(), id: \.self) { key in Text("\(key): \(entries[key]!)") }
            Button("Refresh") { Task { await reload() } }
            Text(message)
        }.task { await reload() }.navigationTitle("Feature B")
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) { Task { do { try await operation(); message = "completed" } catch { message = "error: \(error)" }; await reload() } }
    private func reload() async { value = (try? await FeatureBStore.shared.value()) ?? value; entries = (try? await FeatureBStore.shared.entries()) ?? entries }
}

private enum IntentFixtureFailure: Error { case missingReturnValue }
