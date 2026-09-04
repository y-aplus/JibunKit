import JibunKitCore
import Foundation

public actor ReminderStore {
    public static let shared = ReminderStore()

    private static let messageKey = MiniAppID.reminder.storageKey("message")

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

    public func currentMessage() throws -> String {
        try configuredDefaults().string(forKey: Self.messageKey) ?? ""
    }

    @discardableResult
    public func saveMessage(_ message: String) throws -> String {
        let defaults = try configuredDefaults()
        defaults.set(message, forKey: Self.messageKey)
        return message
    }

    private func configuredDefaults() throws -> UserDefaults {
        if let defaults {
            return defaults
        }
        throw configurationError ?? .missingLogicalIdentifier
    }
}
