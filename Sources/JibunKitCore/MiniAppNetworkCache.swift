import Foundation
import CryptoKit

public enum MiniAppNetworkCacheError: Error, Equatable {
    case invalidCapacity
    case invalidContainer
}

public extension MiniAppContext {
    /// Native URLCache with a Feature/profile-owned disk directory. Retain one
    /// cache per profile and assign it to configurations before creating sessions.
    /// This does not change cookie or credential storage on the configuration.
    func urlCache(memoryCapacity: Int, diskCapacity: Int, containerURL: URL,
                  profile: String = "default") throws -> URLCache {
        guard memoryCapacity >= 0, diskCapacity >= 0 else { throw MiniAppNetworkCacheError.invalidCapacity }
        guard containerURL.isFileURL, id.isValid else { throw MiniAppNetworkCacheError.invalidContainer }
        let profileKey = SHA256.hash(data: Data(profile.utf8)).map { String(format: "%02x", $0) }.joined()
        let directory = containerURL
            .appendingPathComponent("Library/Caches/JibunKit/Features", isDirectory: true)
            .appendingPathComponent(id.storageNamespace, isDirectory: true)
            .appendingPathComponent("Network", isDirectory: true)
            .appendingPathComponent(profileKey, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return URLCache(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, directory: directory)
    }
}
