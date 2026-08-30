import Foundation

public actor CounterStore {
    public static let shared = CounterStore()

    private static let valueKey = "counter.value"

    private let defaults: UserDefaults?
    private let configurationError: SharedGroupResolutionError?

    public init(infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        do {
            let identifier = try SharedGroupResolver().resolve(infoDictionary: infoDictionary)
            guard let defaults = UserDefaults(suiteName: identifier) else {
                throw SharedGroupResolutionError.unavailableUserDefaultsSuite(
                    identifier: identifier
                )
            }
            self.defaults = defaults
            self.configurationError = nil
        } catch let error as SharedGroupResolutionError {
            self.defaults = nil
            self.configurationError = error
        } catch {
            self.defaults = nil
            self.configurationError = .missingLogicalIdentifier
        }
    }

    init(suiteName: String) {
        if let defaults = UserDefaults(suiteName: suiteName) {
            self.defaults = defaults
            self.configurationError = nil
        } else {
            self.defaults = nil
            self.configurationError = .unavailableUserDefaultsSuite(
                identifier: suiteName
            )
        }
    }

    public func currentValue() throws -> Int {
        try configuredDefaults().integer(forKey: Self.valueKey)
    }

    @discardableResult
    public func add(_ amount: Int) throws -> Int {
        let defaults = try configuredDefaults()
        let updatedValue = defaults.integer(forKey: Self.valueKey) + amount
        defaults.set(updatedValue, forKey: Self.valueKey)
        return updatedValue
    }

    private func configuredDefaults() throws -> UserDefaults {
        if let defaults {
            return defaults
        }
        throw configurationError ?? .missingLogicalIdentifier
    }
}
