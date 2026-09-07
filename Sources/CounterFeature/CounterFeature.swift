import JibunKitCore
import Foundation
#if os(iOS)
import WidgetKit
#endif

public extension MiniAppID {
    static let counter = MiniAppID("counter")
}



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

    private let miniAppID: MiniAppID
    private let valueKey: String

    private let defaults: UserDefaults?
    private let configurationError: SharedGroupResolutionError?

    public init(
        context: MiniAppContext,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) {
        self.miniAppID = context.id
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
        self.miniAppID = .counter
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

    /// Pass nil for a standalone app's own defaults; named suites must not
    /// equal that app's bundle identifier.
    public init(context: MiniAppContext, suiteName: String?) {
        self.miniAppID = context.id
        self.valueKey = context.storageKey("value")
        guard let suiteName else {
            self.defaults = .standard
            self.configurationError = nil
            return
        }
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
        self.miniAppID = .counter
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

    private struct BackupState: Codable, Sendable {
        let value: Int
    }

    public nonisolated var backupProvider: MiniAppBackupProvider {
        MiniAppBackupProvider(id: miniAppID, export: {
            let state = BackupState(value: try await self.currentValue())
            return MiniAppBackupEntry(id: self.miniAppID, schemaVersion: 1,
                                      payload: try JSONEncoder().encode(state))
        }, prepare: { entry in
            let state = try entry.decodePayload(BackupState.self, supportedSchema: 1)
            return MiniAppPreparedRestore { try await self.restoreBackup(state) }
        })
    }

    private func restoreBackup(_ state: BackupState) throws {
        let defaults = try configuredDefaults()
        MiniAppStorage.withExclusiveAccess {
            defaults.set(state.value, forKey: valueKey)
        }
        #if os(iOS)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    private func configuredDefaults() throws -> UserDefaults {
        if let defaults {
            return defaults
        }
        throw configurationError ?? .missingLogicalIdentifier
    }
}
