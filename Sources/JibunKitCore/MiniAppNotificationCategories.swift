#if canImport(UserNotifications)
import UserNotifications

/// The host installs the complete union; Features never replace each
/// other's category registrations with separate setNotificationCategories calls.
public enum MiniAppNotificationCategories {
    public enum Failure: Error, Equatable {
        case foreignIdentifier(owner: String, identifier: String)
        case duplicateIdentifier(String)
    }

    public static func merged(_ registrations: [MiniAppID: [UNNotificationCategory]]) throws -> Set<UNNotificationCategory> {
        var identifiers: Set<String> = []
        var result: Set<UNNotificationCategory> = []
        for (owner, categories) in registrations {
            let context = MiniAppContext(id: owner)
            for category in categories {
                guard context.ownsNotificationCategoryIdentifier(category.identifier) else {
                    throw Failure.foreignIdentifier(owner: owner.rawValue, identifier: category.identifier)
                }
                guard identifiers.insert(category.identifier).inserted else {
                    throw Failure.duplicateIdentifier(category.identifier)
                }
                result.insert(category)
            }
        }
        return result
    }
}

/// Serializes owner updates and validates the entire candidate before installation.
@MainActor
public final class MiniAppNotificationCategoryRegistry {
    public enum Failure: Error, Equatable {
        case unregisteredOwner(MiniAppID)
    }

    public static let shared = MiniAppNotificationCategoryRegistry {
        UNUserNotificationCenter.current().setNotificationCategories($0)
    }

    private var registrations: [MiniAppID: [UNNotificationCategory]] = [:]
    private let install: (Set<UNNotificationCategory>) -> Void

    public init(install: @escaping (Set<UNNotificationCategory>) -> Void) {
        self.install = install
    }

    /// The host supplies every registered Feature, including owners with no categories.
    public func configure(_ registrations: [MiniAppID: [UNNotificationCategory]]) throws {
        let categories = try MiniAppNotificationCategories.merged(registrations)
        self.registrations = registrations
        install(categories)
    }

    /// Replaces only this owner's categories. Empty removes them; invalid input changes nothing.
    public func replace(for owner: MiniAppID, with categories: [UNNotificationCategory]) throws {
        guard registrations[owner] != nil else { throw Failure.unregisteredOwner(owner) }
        var candidate = registrations
        candidate[owner] = categories
        let merged = try MiniAppNotificationCategories.merged(candidate)
        registrations = candidate
        install(merged)
    }
}

public extension MiniAppContext {
    @MainActor
    func replaceNotificationCategories(with categories: [UNNotificationCategory]) throws {
        try MiniAppNotificationCategoryRegistry.shared.replace(for: id, with: categories)
    }
}
#endif
