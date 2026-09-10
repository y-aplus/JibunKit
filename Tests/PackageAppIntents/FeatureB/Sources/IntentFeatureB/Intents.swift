import AppIntents
import Foundation

public struct FeatureBIntentPackage: AppIntentsPackage {}

@MainActor
public enum FeatureBValues {
    private static let defaults = UserDefaults(suiteName: "com.jibunkit.intent-fixture.b")!
    public static var value: Int {
        get { defaults.integer(forKey: "value") }
        set { defaults.set(newValue, forKey: "value") }
    }
}

public struct FeatureBAddValueIntent: AppIntent {
    public static let title: LocalizedStringResource = "Add Feature B value"
    public static var supportedModes: IntentModes { [.background] }
    @Parameter(title: "Amount") public var amount: Int
    public init() {}
    public init(amount: Int) { self.amount = amount }
    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        FeatureBValues.value += amount
        return .result(value: FeatureBValues.value)
    }
}
