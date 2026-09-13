#if os(iOS)
import AppIntents
import IntentFeatureA
import IntentFeatureB
import JibunKitCore
import SwiftUI

public extension MiniAppID {
    static let p1IntentA = MiniAppID("intent-fixture-a")
    static let p1IntentB = MiniAppID("intent-fixture-b")
}

private struct P1ABoundary: IntentFeatureA.StoreOperationBoundary {
    func perform<Value: Sendable>(_ operation: @escaping @MainActor @Sendable () async throws -> Value) async throws -> Value {
        try await MiniAppRestoreCoordinator.shared.withStoreAccess(for: .p1IntentA) {
            try Task.checkCancellation(); return try await operation()
        }
    }
}
private struct P1BBoundary: IntentFeatureB.StoreOperationBoundary {
    func perform<Value: Sendable>(_ operation: @escaping @MainActor @Sendable () async throws -> Value) async throws -> Value {
        try await MiniAppRestoreCoordinator.shared.withStoreAccess(for: .p1IntentB) {
            try Task.checkCancellation(); return try await operation()
        }
    }
}

/// Diagnostic-candidate adapter. It configures store boundaries only; the
/// normal host's single MiniAppManagement owns admission and removal.
@MainActor
public enum P1IntentsProbe {
    public static let definitionA = MiniAppDefinition(
        id: .p1IntentA, title: "Intent診断A", systemImage: "a.circle",
        removal: MiniAppRemovalProvider(id: .p1IntentA, dataDescription: "Intent診断Aの値と候補") {
            await FeatureAStore.shared.removeAllReserved()
        }
    ) { _ in P1IntentFeatureView(owner: "A") }
    public static let definitionB = MiniAppDefinition(
        id: .p1IntentB, title: "Intent診断B", systemImage: "b.circle",
        removal: MiniAppRemovalProvider(id: .p1IntentB, dataDescription: "Intent診断Bの値と候補") {
            await FeatureBStore.shared.removeAllReserved()
        }
    ) { _ in P1IntentFeatureView(owner: "B") }

    /// Call after forcing MiniAppRegistry.management initialization and before
    /// constructing UI. Never put this only in an enabled Feature hook.
    public static func bootstrap() {
        FeatureAStore.shared.configure(boundary: P1ABoundary())
        FeatureBStore.shared.configure(boundary: P1BBoundary())
    }
}

private struct P1IntentFeatureView: View {
    let owner: String
    @State private var value = 0
    @State private var title = "candidate"
    @State private var message = "ready"
    @State private var entries: [String: String] = [:]
    var body: some View {
        Form {
            Text("\(owner):\(value)").accessibilityIdentifier("p1.intent.value")
            TextField("候補名", text: $title)
            Button("候補を保存") { run { try await saveCandidate() } }
            Button("1を追加") { run { value = try await addOne() } }.accessibilityIdentifier("p1.intent.add")
            Button("次の保存を失敗") { injectFailure(); message = "armed failure" }
            Button("次の保存を5秒遅延") { injectDelay(); message = "armed delay" }
            Button("値と候補を再読込") { run { try await reload() } }
            ForEach(entries.keys.sorted(), id: \.self) { key in Text("\(key): \(entries[key]!)") }
            Text(message).accessibilityIdentifier("p1.intent.status")
        }.task { do { try await reload() } catch { message = "error: \(error)" } }
    }
    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        Task { do { try await operation(); try await reload(); message = "completed" } catch { message = "error: \(error)" } }
    }
    private func reload() async throws {
        value = try await currentValue()
        if owner == "A" { entries = try await FeatureAStore.shared.entries() }
        else { entries = try await FeatureBStore.shared.entries() }
    }
    private func currentValue() async throws -> Int {
        if owner == "A" { return try await FeatureAStore.shared.value() }
        return try await FeatureBStore.shared.value()
    }
    private func addOne() async throws -> Int {
        if owner == "A" { return try await FeatureAAddValueIntent(amount: 1).perform().value }
        return try await FeatureBAddValueIntent(amount: 1).perform().value
    }
    private func saveCandidate() async throws {
        if owner == "A" { var entries = try await FeatureAStore.shared.entries(); entries["a-candidate"] = title; try await FeatureAStore.shared.replaceEntries(entries) }
        else { var entries = try await FeatureBStore.shared.entries(); entries["b-candidate"] = title; try await FeatureBStore.shared.replaceEntries(entries) }
    }
    private func injectFailure() {
        if owner == "A" { FeatureAStore.shared.injectNextSaveFailure() }
        else { FeatureBStore.shared.injectNextSaveFailure() }
    }
    private func injectDelay() {
        if owner == "A" { FeatureAStore.shared.delayNextSave(nanoseconds: 5_000_000_000) }
        else { FeatureBStore.shared.delayNextSave(nanoseconds: 5_000_000_000) }
    }
}
#endif
