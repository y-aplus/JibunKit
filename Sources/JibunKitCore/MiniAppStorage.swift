import Foundation

/// Shared App Group UserDefaults resolution for Feature stores.
/// The storage key itself stays Feature-owned via `MiniAppContext.storageKey(_:)`;
/// only the suite resolution is shared here.
public enum MiniAppStorage {
    public static func sharedDefaults(
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) throws -> UserDefaults {
        let identifier = try SharedGroupResolver().resolve(infoDictionary: infoDictionary)
        guard let defaults = UserDefaults(suiteName: identifier) else {
            throw SharedGroupResolutionError.unavailableUserDefaultsSuite(
                identifier: identifier
            )
        }
        return defaults
    }
}
