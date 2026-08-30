#if os(iOS)
import CounterFeature
import SwiftUI

struct CounterScreen: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var value = 0
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 16) {
            Text("カウンター")
                .font(.headline)
            Text(value, format: .number)
                .font(.largeTitle)
                .monospacedDigit()
            Button("1を追加") {
                Task {
                    await addOne()
                }
            }
            .buttonStyle(.borderedProminent)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
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
            value = try await CounterStore.shared.currentValue()
            errorMessage = nil
        } catch {
            errorMessage = "共有値を読み込めません"
        }
    }

    @MainActor
    private func addOne() async {
        do {
            value = try await CounterStore.shared.add(1)
            errorMessage = nil
        } catch {
            errorMessage = "共有値を更新できません"
        }
    }
}
#endif
