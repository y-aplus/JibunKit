#if os(iOS)
import AppIntents
import CounterFeature

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

    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let updatedValue = try await CounterStore.shared.add(amount)
        return .result(value: updatedValue)
    }
}
#endif
