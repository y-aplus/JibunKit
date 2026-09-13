import AppIntents
import Foundation

public struct FeatureBIntentPackage: AppIntentsPackage {}

public struct FeatureBAddValueIntent: AppIntent {
    public static let title: LocalizedStringResource = "Add Feature B value"
    public static var supportedModes: IntentModes { [.background] }
    @Parameter(title: "Amount") public var amount: Int
    public init() {}
    public init(amount: Int) { self.amount = amount }
    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let value = try await FeatureBStore.shared.add(amount)
        return .result(value: value)
    }
}
