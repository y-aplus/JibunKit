import Foundation

public enum MiniAppID: String, CaseIterable, Hashable, Sendable {
    case counter
    case reminder

    public var storageNamespace: String {
        rawValue
    }

    public var notificationRequestIdentifier: String {
        "jibunkit.\(rawValue).notification"
    }

    public func storageKey(_ key: String) -> String {
        "\(storageNamespace).\(key)"
    }
}

public enum MiniAppNotificationRoute {
    public static let miniAppIDUserInfoKey = "JibunKitMiniAppID"

    public static func resolve(userInfo: [AnyHashable: Any]) -> MiniAppID? {
        guard let rawValue = userInfo[miniAppIDUserInfoKey] as? String else {
            return nil
        }
        return MiniAppID(rawValue: rawValue)
    }
}
