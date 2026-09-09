import Foundation

public struct MiniAppID: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.init(rawValue: rawValue)
    }

    public var isValid: Bool {
        guard let first = rawValue.utf8.first,
              Self.isLowercaseLetter(first)
        else {
            return false
        }

        return rawValue.utf8.allSatisfy { byte in
            Self.isLowercaseLetter(byte)
                || (48...57).contains(byte)
                || byte == 45
                || byte == 46
                || byte == 95
        }
    }

    public var storageNamespace: String {
        // '%' is not a valid ID character, so this is unambiguous. Escaping
        // only the separator keeps all shipped undotted IDs byte-compatible.
        rawValue.replacingOccurrences(of: ".", with: "%2E")
    }

    public var notificationRequestIdentifier: String {
        "jibunkit.\(storageNamespace).notification"
    }

    public func storageKey(_ key: String) -> String {
        "\(storageNamespace).\(key)"
    }

    private static func isLowercaseLetter(_ byte: UInt8) -> Bool {
        (97...122).contains(byte)
    }
}

public struct MiniAppContext: Hashable, Sendable {
    public let id: MiniAppID

    public init(id: MiniAppID) {
        precondition(id.isValid, "Mini-app context requires a valid ID.")
        self.id = id
    }

    public func storageKey(_ key: String) -> String {
        id.storageKey(key)
    }

    public var notificationRequestIdentifier: String {
        id.notificationRequestIdentifier
    }

    /// A stable Feature-owned key identifies one of many notifications.
    /// Encoding keeps arbitrary keys distinct without exposing ID separators.
    public func notificationRequestIdentifier(for key: String) -> String {
        notificationRequestIdentifier + "." + Data(key.utf8).base64EncodedString()
    }

    /// Includes the original single-notification ID for backward compatibility.
    /// This is namespace matching, not authorization between Features.
    public func ownsNotificationRequestIdentifier(_ identifier: String) -> Bool {
        identifier == notificationRequestIdentifier
            || identifier.hasPrefix(notificationRequestIdentifier + ".")
    }

    public var notificationUserInfo: [String: String] {
        [MiniAppNotificationRoute.miniAppIDUserInfoKey: id.rawValue]
    }

    public func notificationUserInfo(destination: String) -> [String: String]? {
        guard MiniAppLink.url(for: id, destination: destination) != nil else { return nil }
        var info = notificationUserInfo
        info[MiniAppNotificationRoute.destinationUserInfoKey] = destination
        return info
    }
}

public enum MiniAppNotificationRoute {
    public static let miniAppIDUserInfoKey = "JibunKitMiniAppID"
    public static let destinationUserInfoKey = "JibunKitDestination"

    public static func candidateRoute(userInfo: [AnyHashable: Any]) -> MiniAppRoute? {
        guard let id = candidate(userInfo: userInfo) else { return nil }
        guard let raw = userInfo[destinationUserInfoKey] else {
            return MiniAppRoute(id: id, destination: nil)
        }
        guard let destination = raw as? String,
              MiniAppLink.url(for: id, destination: destination) != nil else { return nil }
        return MiniAppRoute(id: id, destination: destination)
    }

    public static func candidate(userInfo: [AnyHashable: Any]) -> MiniAppID? {
        guard let rawValue = userInfo[miniAppIDUserInfoKey] as? String else {
            return nil
        }
        let miniAppID = MiniAppID(rawValue: rawValue)
        return miniAppID.isValid ? miniAppID : nil
    }

    public static func resolve(
        userInfo: [AnyHashable: Any],
        registeredIDs: Set<MiniAppID>
    ) -> MiniAppID? {
        guard let miniAppID = candidate(userInfo: userInfo),
              registeredIDs.contains(miniAppID)
        else {
            return nil
        }
        return miniAppID
    }
}
