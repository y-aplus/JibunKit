import AppIntents
import Foundation

public struct FeatureAIntentPackage: AppIntentsPackage {}

@MainActor
public enum FeatureAValues {
    private static let defaults = UserDefaults(suiteName: "com.jibunkit.intent-fixture.a")!
    public static var value: Int {
        get { defaults.integer(forKey: "value") }
        set { defaults.set(newValue, forKey: "value") }
    }
}

public struct FeatureAAddValueIntent: AppIntent {
    public static let title: LocalizedStringResource = "Add Feature A value"
    public static var supportedModes: IntentModes { [.background] }
    @Parameter(title: "Amount") public var amount: Int
    public init() {}
    public init(amount: Int) { self.amount = amount }
    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        FeatureAValues.value += amount
        return .result(value: FeatureAValues.value)
    }
}
