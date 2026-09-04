import JibunKitCore
import Foundation

public extension MiniAppID {
    static let reminder = MiniAppID("reminder")
}

public actor ReminderStore {
    public static let shared = ReminderStore(context: MiniAppContext(id: .reminder))

    private let messageKey: String

    private let defaults: UserDefaults?
    private let configurationError: SharedGroupResolutionError?

    public init(
        context: MiniAppContext,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) {
        self.messageKey = context.storageKey("message")
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

    public init(infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
        self.messageKey = MiniAppContext(id: .reminder).storageKey("message")
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

    init(context: MiniAppContext, suiteName: String) {
        self.messageKey = context.storageKey("message")
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
        self.messageKey = MiniAppContext(id: .reminder).storageKey("message")
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

    public func currentMessage() throws -> String {
        try configuredDefaults().string(forKey: messageKey) ?? ""
    }

    @discardableResult
    public func saveMessage(_ message: String) throws -> String {
        let defaults = try configuredDefaults()
        defaults.set(message, forKey: messageKey)
        return message
    }

    private func configuredDefaults() throws -> UserDefaults {
        if let defaults {
            return defaults
        }
        throw configurationError ?? .missingLogicalIdentifier
    }
}
