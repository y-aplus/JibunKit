import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// An in-memory native request snapshot that can cross the delegate's executor
/// boundary without sharing mutable userInfo objects. Not a backup format.
public struct MiniAppNotificationRequestSnapshot: Sendable, Equatable {
    private let archive: Data

    #if canImport(UserNotifications)
    public init(request: UNNotificationRequest) throws {
        archive = try NSKeyedArchiver.archivedData(withRootObject: request, requiringSecureCoding: true)
    }

    /// Returns a fresh native request, including content, userInfo and trigger.
    /// Attachment file URLs retain their OS-managed lifetime; no files are copied.
    public func request() throws -> UNNotificationRequest {
        guard let request = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: UNNotificationRequest.self, from: archive
        ) else { throw Failure.missingRequest }
        return request
    }

    private enum Failure: Error { case missingRequest }
    #endif
}
