import AppIntents
import Foundation

public struct FeatureAIntentPackage: AppIntentsPackage {}

public struct FeatureAAddValueIntent: AppIntent {
    public static let title: LocalizedStringResource = "Add Feature A value"
    public static var supportedModes: IntentModes { [.background] }
    @Parameter(title: "Amount") public var amount: Int
    public init() {}
    public init(amount: Int) { self.amount = amount }
    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let value = try await FeatureAStore.shared.add(amount)
        return .result(value: value)
    }
}
