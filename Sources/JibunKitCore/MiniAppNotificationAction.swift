import Foundation

public struct MiniAppNotificationAction: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case open, dismiss, custom(String)
    }
    public let kind: Kind
    public let requestIdentifier: String
    public let destination: String?
    public let userText: String?

    public init(kind: Kind, requestIdentifier: String, destination: String?, userText: String?) {
        self.kind = kind
        self.requestIdentifier = requestIdentifier
        self.destination = destination
        self.userText = userText
    }
}

@MainActor
public enum MiniAppNotificationActionDelivery {
    /// Resolve only the payload owner. Missing/unsupported actions never fall
    /// through to another Feature. Only the default open action changes routing.
    public static func deliver(
        _ action: MiniAppNotificationAction,
        route: MiniAppRoute?,
        handlerForOwner: (MiniAppID) -> (@MainActor (MiniAppNotificationAction) async -> Void)?,
        open: (MiniAppRoute?) -> Void
    ) async {
        if action.kind == .open { open(route) }
        if let route, let handler = handlerForOwner(route.id) { await handler(action) }
    }
}
