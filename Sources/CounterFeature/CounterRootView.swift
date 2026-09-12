#if os(iOS)
import JibunKitCore
import SwiftUI

public struct CounterRootView: View {
    private let store: CounterStore

    @Environment(\.scenePhase) private var scenePhase
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
            Text("カウンター")
                .font(.headline)
            if let value {
                Text(value, format: .number)
                    .accessibilityIdentifier("counter.value")
                    .font(.largeTitle)
                    .monospacedDigit()
            } else if errorMessage == nil {
                ProgressView("保存値を読み込んでいます")
                    .accessibilityIdentifier("counter.loading")
            }
            Button("1を追加") {
                Task {
                    await addOne()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(value == nil)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                Button("再読み込み") { Task { await loadValue() } }
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
            errorMessage = "共有値を読み込めません"
        }
    }

    @MainActor
    private func addOne() async {
        do {
            value = try await store.add(1)
            errorMessage = nil
        } catch {
            errorMessage = "共有値を更新できません"
        }
    }
}
#endif
