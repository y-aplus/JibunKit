import Foundation

/// Narrowly models host window creation and destruction without pretending a
/// request means iPadOS actually created or closed a window.
@MainActor
public protocol MiniAppWindowSceneRequesting: AnyObject {
    func requestWindow(userActivity: NSUserActivity?, onFailure: @escaping @MainActor @Sendable (Error) -> Void)
    func destroyWindow(sessionID: MiniAppWindowSessionID, onFailure: @escaping @MainActor @Sendable (Error) -> Void) -> Bool
}

#if canImport(UIKit) && os(iOS)
import UIKit

@MainActor
public final class MiniAppUIKitWindowSceneRequester: MiniAppWindowSceneRequesting {
    private let application: UIApplication

    public init(application: UIApplication = .shared) { self.application = application }

    public func requestWindow(
        userActivity: NSUserActivity?,
        onFailure: @escaping @MainActor @Sendable (Error) -> Void
    ) {
        let request = UISceneSessionActivationRequest(
            role: .windowApplication, userActivity: userActivity, options: nil
        )
        application.activateSceneSession(for: request, errorHandler: onFailure)
    }

    public func destroyWindow(
        sessionID: MiniAppWindowSessionID,
        onFailure: @escaping @MainActor @Sendable (Error) -> Void
    ) -> Bool {
        guard let session = application.openSessions.first(where: {
            $0.persistentIdentifier == sessionID.rawValue
        }) else { return false }
        application.requestSceneSessionDestruction(session, options: nil, errorHandler: onFailure)
        return true
    }
}
#endif
