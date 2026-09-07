import Foundation

/// Shared App Group UserDefaults resolution for Feature stores.
/// The storage key itself stays Feature-owned via `MiniAppContext.storageKey(_:)`;
/// only the suite resolution is shared here.
public enum MiniAppStorage {
    private static let accessLock = NSLock()

    /// Serializes a synchronous read-modify-write across Store instances in
    /// this process. Every writer of the shared value must use this boundary.
    /// This is not a rollback transaction or a cross-process lock. Do not nest
    /// calls or perform asynchronous work inside the closure.
    public static func withExclusiveAccess<Result>(
        _ operation: () throws -> Result
    ) rethrows -> Result {
        accessLock.lock()
        defer { accessLock.unlock() }
        return try operation()
    }

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
