import JibunKitCore
import Foundation

public enum CounterStoreError: Error, Equatable, LocalizedError, Sendable {
    case valueOutOfRange

    public var errorDescription: String? {
        switch self {
        case .valueOutOfRange:
            "カウンターの値が範囲を超えます。"
        }
    }
}

public actor CounterStore {
    public static let shared = CounterStore()

    private static let valueKey = MiniAppID.counter.storageKey("value")

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
        let updatedValue = try Self.updatedValue(
            defaults.integer(forKey: Self.valueKey),
            adding: amount
        )
        defaults.set(updatedValue, forKey: Self.valueKey)
        return updatedValue
    }

    static func updatedValue(_ currentValue: Int, adding amount: Int) throws -> Int {
        let (updatedValue, overflow) = currentValue.addingReportingOverflow(amount)
        guard !overflow else {
            throw CounterStoreError.valueOutOfRange
        }
        return updatedValue
    }

    private func configuredDefaults() throws -> UserDefaults {
        if let defaults {
            return defaults
        }
        throw configurationError ?? .missingLogicalIdentifier
    }
}
