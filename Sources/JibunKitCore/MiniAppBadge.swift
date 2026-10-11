import Foundation
#if os(iOS)
import UserNotifications
#endif

/// The app icon badge is one number for the whole app. Each Feature sets only
/// its own count; the coordinator shows the sum of enabled owners, so one
/// Feature can no longer overwrite another's badge.
@MainActor
public final class MiniAppBadgeCoordinator {
    public nonisolated static let defaultStorageKey = "jibunkit.badge-counts"

    private let defaults: UserDefaults
    private let storageKey: String
    private let apply: @MainActor (Int) async throws -> Void
    /// nil until the host reports admission; every stored owner counts meanwhile.
    private var enabledOwners: Set<MiniAppID>?
    /// The owners the current Focus shows; nil when no Focus filter applies.
    private var focusedOwners: Set<MiniAppID>?

    public init(defaults: UserDefaults, storageKey: String = MiniAppBadgeCoordinator.defaultStorageKey,
                apply: @escaping @MainActor (Int) async throws -> Void) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.apply = apply
    }

    #if os(iOS)
    private static var sharedInstance: MiniAppBadgeCoordinator?

    /// Created on first use on the main actor. A static stored initializer
    /// would run outside the main actor under Swift 6 isolation rules.
    public static var shared: MiniAppBadgeCoordinator {
        if let sharedInstance { return sharedInstance }
        let created = MiniAppBadgeCoordinator(defaults: .standard, storageKey: defaultStorageKey) { try await MiniAppBadgeCoordinator.setIconBadge($0) }
        sharedInstance = created
        return created
    }

    // Nonisolated so the notification center is used off the main actor.
    private nonisolated static func setIconBadge(_ count: Int) async throws {
        try await UNUserNotificationCenter.current().setBadgeCount(count)
    }
    #endif

    public func count(for owner: MiniAppID) -> Int {
        counts[owner.rawValue] ?? 0
    }

    /// The number currently shown on the icon.
    public var total: Int {
        counts.reduce(0) { sum, entry in
            let owner = MiniAppID(entry.key)
            guard enabledOwners?.contains(owner) ?? true, focusedOwners?.contains(owner) ?? true else { return sum }
            let (value, overflow) = sum.addingReportingOverflow(entry.value)
            return overflow ? Int.max : value
        }
    }

    /// Stores this owner's count (negative values become 0) and updates the icon.
    public func setCount(_ count: Int, for owner: MiniAppID) async throws {
        guard owner.isValid else { throw MiniAppBackupError.invalidEntry }
        var next = counts
        next[owner.rawValue] = count > 0 ? count : nil
        defaults.set(next, forKey: storageKey)
        try await apply(total)
    }

    /// Host management reports admission; disabled owners stop contributing.
    public func setEnabledOwners(_ owners: Set<MiniAppID>) async throws {
        enabledOwners = owners
        try await apply(total)
    }

    /// The host's Focus filter: owners it hides stop contributing until the
    /// Focus ends. Their stored counts are kept.
    public func setFocusedOwners(_ owners: Set<MiniAppID>?) async throws {
        focusedOwners = owners
        try await apply(total)
    }

    /// Used when an owner is unregistered, like its pending notifications.
    public func removeCount(for owner: MiniAppID) async throws {
        try await setCount(0, for: owner)
    }

    private var counts: [String: Int] {
        (defaults.dictionary(forKey: storageKey) ?? [:]).compactMapValues { value in
            (value as? Int).flatMap { $0 > 0 ? $0 : nil }
        }
    }
}

#if os(iOS)
public extension MiniAppContext {
    /// Sets this Feature's share of the app icon badge. Do not set
    /// `UNNotificationContent.badge`: that replaces every Feature's count.
    @MainActor
    func setBadgeCount(_ count: Int) async throws {
        try await MiniAppBadgeCoordinator.shared.setCount(count, for: id)
    }
}
#endif
