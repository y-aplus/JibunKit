#if os(iOS)
import AppIntents
import Foundation
import CounterFeature
import JibunKitCore

struct AddCounterValueIntent: AppIntent {
    static let title: LocalizedStringResource = "カウンターに追加"
    static let description = IntentDescription("指定した数をカウンターへ追加し、更新後の値を返します。")
    static var supportedModes: IntentModes { [.background] }

    @Parameter(title: "追加する数")
    var amount: Int

    static var parameterSummary: some ParameterSummary {
        Summary("カウンターに \(\.$amount) を追加")
    }

    init() {}

    init(amount: Int) {
        self.amount = amount
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        // Initialize persisted host admission even when Shortcuts cold-launches
        // the app without constructing a Feature screen.
        guard MiniAppRegistry.management.isEnabled(.counter) else { throw CounterUnavailable() }
        let amount = amount
        let updatedValue = try await MiniAppRestoreCoordinator.shared.withStoreAccess(for: .counter) {
            try await CounterStore.shared.add(amount)
        }
        return .result(value: updatedValue)
    }
}

private struct CounterUnavailable: LocalizedError {
    var errorDescription: String? { "カウンターは無効化または削除されています。JibunKitの管理画面で再有効化してください。" }
}
#endif
