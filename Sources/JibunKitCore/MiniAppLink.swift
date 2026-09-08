import Foundation

/// Opens a registered Feature's root. Links never execute Feature operations.
public enum MiniAppLink {
    public static func url(for id: MiniAppID) -> URL? {
        guard id.isValid else { return nil }
        var components = URLComponents()
        components.scheme = "jibunkit"
        components.host = "mini-app"
        components.path = "/\(id.rawValue)"
        return components.url
    }

    public static func resolve(_ url: URL, registeredIDs: Set<MiniAppID>) -> MiniAppID? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "jibunkit",
              components.host?.lowercased() == "mini-app",
              components.user == nil, components.password == nil, components.port == nil,
              components.query == nil, components.fragment == nil,
              components.path.hasPrefix("/")
        else { return nil }
        let id = MiniAppID(String(components.path.dropFirst()))
        guard id.isValid, registeredIDs.contains(id) else { return nil }
        return id
    }
}
