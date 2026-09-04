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
        rawValue
    }

    public var notificationRequestIdentifier: String {
        "jibunkit.\(rawValue).notification"
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

    public var notificationUserInfo: [String: String] {
        [MiniAppNotificationRoute.miniAppIDUserInfoKey: id.rawValue]
    }
}

public enum MiniAppNotificationRoute {
    public static let miniAppIDUserInfoKey = "JibunKitMiniAppID"

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
