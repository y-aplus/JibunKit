#if canImport(UserNotifications)
import UserNotifications

/// The host installs the complete union once; Features never replace each
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
#endif
