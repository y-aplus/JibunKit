#if os(iOS)
import JibunKitCore
import SwiftUI

public struct CounterRootView: View {
    private let store: CounterStore

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.miniAppLifetime) private var lifetime
    @State private var value: Int?
    @State private var errorMessage: String?

    public init(context: MiniAppContext) {
        store = CounterStore(context: context)
    }

    public init(store: CounterStore) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text("Counter", bundle: .module)
                .font(.headline)
            if let value {
                Text(value, format: .number)
                    .accessibilityIdentifier("counter.value")
                    .font(.largeTitle)
                    .monospacedDigit()
            } else if errorMessage == nil {
                ProgressView { Text("Loading the saved value", bundle: .module) }
                    .accessibilityIdentifier("counter.loading")
            }
            Button {
                if let lifetime {
                    guard lifetime.isStartAllowed, let runtime = lifetime.runtime else { return }
                    do { try runtime.start { await addOne() } }
                    catch { errorMessage = String(localized: "This app has ended", bundle: .module) }
                } else {
                    Task { await addOne() }
                }
            } label: {
                Text("Add 1", bundle: .module)
            }
            .buttonStyle(.borderedProminent)
            .disabled(value == nil)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                Button { Task { await loadValue() } } label: { Text("Reload", bundle: .module) }
            }
        }
        .padding()
        .task {
            await loadValue()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await loadValue()
            }
        }
    }

    @MainActor
    private func loadValue() async {
        do {
            value = try await store.currentValue()
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Can’t load the shared value", bundle: .module)
        }
    }

    @MainActor
    private func addOne() async {
        do {
            value = try await store.add(1)
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Can’t update the shared value", bundle: .module)
        }
    }
}
#endif
