import JibunKitCore
import Foundation

public extension MiniAppID {
    static let counter = MiniAppID("counter")
}

#if os(iOS)
public enum CounterMiniApp {
    @MainActor
    public static let definition = MiniAppDefinition(
        id: .counter,
        title: "カウンター",
        systemImage: "number"
    ) { context in
        CounterRootView(context: context)
    }
}
#endif

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
    public static let shared = CounterStore(context: MiniAppContext(id: .counter))

    private let valueKey: String

    private let defaults: UserDefaults?
    private let configurationError: SharedGroupResolutionError?

    public init(
        context: MiniAppContext,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) {
        self.valueKey = context.storageKey("value")
        do {
            self.defaults = try MiniAppStorage.sharedDefaults(infoDictionary: infoDictionary)
            self.configurationError = nil
        } catch let error as SharedGroupResolutionError {
            self.defaults = nil
            self.configurationError = error
        } catch {
            self.defaults = nil
            self.configurationError = .missingLogicalIdentifier
        }
    }

    public init(infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        self.valueKey = MiniAppContext(id: .counter).storageKey("value")
        do {
            self.defaults = try MiniAppStorage.sharedDefaults(infoDictionary: infoDictionary)
            self.configurationError = nil
        } catch let error as SharedGroupResolutionError {
            self.defaults = nil
            self.configurationError = error
        } catch {
            self.defaults = nil
            self.configurationError = .missingLogicalIdentifier
        }
    }

    init(context: MiniAppContext, suiteName: String) {
        self.valueKey = context.storageKey("value")
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

    init(suiteName: String) {
        self.valueKey = MiniAppContext(id: .counter).storageKey("value")
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
        try configuredDefaults().integer(forKey: valueKey)
    }

    @discardableResult
    public func add(_ amount: Int) throws -> Int {
        let defaults = try configuredDefaults()
        return try MiniAppStorage.withExclusiveAccess {
            let updatedValue = try Self.updatedValue(
                defaults.integer(forKey: valueKey),
                adding: amount
            )
            defaults.set(updatedValue, forKey: valueKey)
            return updatedValue
        }
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
