import Foundation

/// An app has at most one Notification Service extension and one Notification
/// Content extension. The host owns both and hands each notification only to
/// the Feature that owns it, or leaves it unchanged.
public enum MiniAppNotificationOwner {
    /// A notification's owner among `candidates`. An explicit owner in the
    /// payload wins and is never replaced by identifier matching; otherwise the
    /// request or category identifier must match exactly one candidate's namespace.
    public static func resolve(requestIdentifier: String, categoryIdentifier: String,
                               userInfo: [AnyHashable: Any], candidates: [MiniAppID]) -> MiniAppID? {
        let valid = candidates.filter(\.isValid)
        if userInfo[MiniAppNotificationRoute.miniAppIDUserInfoKey] != nil {
            guard let owner = MiniAppNotificationRoute.candidate(userInfo: userInfo), valid.contains(owner) else { return nil }
            return owner
        }
        let matches = valid.filter { id in
            let context = MiniAppContext(id: id)
            return context.ownsNotificationRequestIdentifier(requestIdentifier)
                || context.ownsNotificationCategoryIdentifier(categoryIdentifier)
        }
        return matches.count == 1 ? matches[0] : nil
    }
}

#if os(iOS)
import UIKit
import UserNotifications
import UserNotificationsUI

/// A Feature's part of the host's Notification Service extension. It has the
/// same contract as `UNNotificationServiceExtension`: call the content handler
/// exactly once, and deliver the best available content when time expires.
/// The system may call it off the main thread.
public protocol MiniAppNotificationServiceHandling: AnyObject {
    func didReceive(_ request: UNNotificationRequest,
                    withContentHandler contentHandler: @escaping @Sendable (UNNotificationContent) -> Void)
    func serviceExtensionTimeWillExpire()
}

/// Subclass in the host's service extension target and return the Features'
/// handlers. A notification without an owning handler is delivered unchanged.
open class MiniAppNotificationService: UNNotificationServiceExtension {
    private var active: (any MiniAppNotificationServiceHandling)?

    /// Override. Called once per notification; the owner is resolved among its keys.
    open func makeHandlers() -> [MiniAppID: any MiniAppNotificationServiceHandling] { [:] }

    open override func didReceive(_ request: UNNotificationRequest,
                                  withContentHandler contentHandler: @escaping @Sendable (UNNotificationContent) -> Void) {
        let handlers = makeHandlers()
        guard let owner = MiniAppNotificationOwner.resolve(
            requestIdentifier: request.identifier, categoryIdentifier: request.content.categoryIdentifier,
            userInfo: request.content.userInfo, candidates: Array(handlers.keys)),
              let handler = handlers[owner] else {
            contentHandler(request.content)
            return
        }
        active = handler
        handler.didReceive(request, withContentHandler: contentHandler)
    }

    open override func serviceExtensionTimeWillExpire() {
        active?.serviceExtensionTimeWillExpire()
    }
}

/// Subclass as the principal class of the host's Notification Content
/// extension and return the owning Feature's view controller. List the Features'
/// category identifiers (`MiniAppContext.notificationCategoryIdentifier(for:)`)
/// in the extension's `UNNotificationExtensionCategory`.
open class MiniAppNotificationContentViewController: UIViewController, UNNotificationContentExtension {
    private var child: (UIViewController & UNNotificationContentExtension)?

    /// Override. The owners whose categories this extension displays.
    open var owners: [MiniAppID] { [] }

    /// Override. Return nil to show the system's default content.
    open func makeContentViewController(for owner: MiniAppID) -> (UIViewController & UNNotificationContentExtension)? { nil }

    public func didReceive(_ notification: UNNotification) {
        let request = notification.request
        if child == nil, let owner = MiniAppNotificationOwner.resolve(
            requestIdentifier: request.identifier, categoryIdentifier: request.content.categoryIdentifier,
            userInfo: request.content.userInfo, candidates: owners),
           let controller = makeContentViewController(for: owner) {
            addChild(controller)
            controller.view.frame = view.bounds
            controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(controller.view)
            controller.didMove(toParent: self)
            preferredContentSize = controller.preferredContentSize
            child = controller
        }
        child?.didReceive(notification)
    }

    /// A Feature controller that does not handle responses forwards them to the app.
    public func didReceive(_ response: UNNotificationResponse) async -> UNNotificationContentExtensionResponseOption {
        guard let child, let option = await child.didReceive?(response) else { return .dismissAndForwardAction }
        return option
    }
}
#endif
