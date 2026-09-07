import JibunKitCore
import Foundation
#if os(iOS)
import UserNotifications
#endif

public extension MiniAppID {
    static let reminder = MiniAppID("reminder")
}

#if os(iOS)
public enum ReminderMiniApp {
    @MainActor
    public static let definition = MiniAppDefinition(
        id: .reminder,
        title: "リマインダー",
        systemImage: "bell",
        backup: ReminderStore.shared.backupProvider
    ) { context in
        ReminderRootView(context: context)
    }
}
#endif

public actor ReminderStore {
    public static let shared = ReminderStore(context: MiniAppContext(id: .reminder))

    private let miniAppID: MiniAppID
    private let messageKey: String

    private let defaults: UserDefaults?
    private let configurationError: SharedGroupResolutionError?

    public init(
        context: MiniAppContext,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) {
        self.miniAppID = context.id
        self.messageKey = context.storageKey("message")
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
        self.miniAppID = .reminder
        self.messageKey = MiniAppContext(id: .reminder).storageKey("message")
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
        self.miniAppID = context.id
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
        self.miniAppID = .reminder
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

    private struct BackupState: Codable, Sendable {
        let message: String
    }

    public nonisolated var backupProvider: MiniAppBackupProvider {
        MiniAppBackupProvider(id: miniAppID, export: {
            let state = BackupState(message: try await self.currentMessage())
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
            defaults.set(state.message, forKey: messageKey)
        }
        #if os(iOS)
        // A saved message does not encode a future notification schedule.
        let center = UNUserNotificationCenter.current()
        let identifier = MiniAppContext(id: miniAppID).notificationRequestIdentifier
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        #endif
    }

    private func configuredDefaults() throws -> UserDefaults {
        if let defaults {
            return defaults
        }
        throw configurationError ?? .missingLogicalIdentifier
    }
}
