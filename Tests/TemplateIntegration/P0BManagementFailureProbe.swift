// Copied only into the isolated signed CI host, never into a distributed IPA.
#if os(iOS)
import CounterFeature
import JibunKitCore
import SwiftUI

@MainActor
enum P0BManagementFailureProbe {
    static let id = MiniAppID("p0b-removal-failure")
    private static let store = CounterStore(
        context: MiniAppContext(id: id),
        suiteName: "P0BManagementFailureProbe.Store")
    private static let unregister = P0BUnregisterFailure(store: store)
    static let lifetime = MiniAppFeatureLifetime(id: id)

    static let definition = MiniAppDefinition(
        id: id,
        title: "削除失敗診断",
        systemImage: "exclamationmark.arrow.triangle.2.circlepath",
        lifetime: lifetime,
        removal: MiniAppRemovalProvider(
            id: id,
            dataDescription: "診断用に保存したカウンター値",
            removeData: { try await store.removalProvider.removeData() }),
        onUnregister: { try await unregister.run() }
    ) { _ in
        P0BManagementFailureProbeView(store: store)
    }
}

private struct P0BManagementFailureProbeView: View {
    let store: CounterStore
    @State private var value: Int?
    @State private var result = "loading"

    var body: some View {
        VStack(spacing: 16) {
            if let value {
                Text(value, format: .number)
                    .font(.largeTitle)
                    .monospacedDigit()
                    .accessibilityIdentifier("p0b.failure.value")
            } else {
                ProgressView("保存値を読み込んでいます")
            }
            Text(result)
                .accessibilityIdentifier("p0b.failure.result")
            Button("診断値を1増やす") {
                Task {
                    do {
                        value = try await store.add(1)
                        result = "saved=\(value ?? -1)"
                    } catch {
                        result = "failed: \(error)"
                    }
                }
            }
            .disabled(value == nil)
            .accessibilityIdentifier("p0b.failure.increment")
        }
        .padding()
        .navigationTitle("削除失敗診断")
        .task {
            do {
                value = try await store.currentValue()
                result = "loaded=\(value ?? -1)"
            } catch {
                result = "failed: \(error)"
            }
        }
    }
}

@MainActor
private final class P0BUnregisterFailure {
    private let store: CounterStore
    private var hasFailed = false

    init(store: CounterStore) { self.store = store }

    func run() async throws {
        guard !hasFailed else { return }
        hasFailed = true
        let saved = try await store.currentValue()
        throw P0BExpectedUnregisterFailure(saved: saved)
    }
}

private struct P0BExpectedUnregisterFailure: Error, CustomStringConvertible {
    let saved: Int
    var description: String { "diagnostic unregister failed once; saved=\(saved)" }
}
#endif
