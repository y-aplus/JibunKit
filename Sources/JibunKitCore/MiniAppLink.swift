import Foundation

/// An address, not an instruction to mutate Feature data.
public struct MiniAppRoute: Equatable, Sendable {
    public let id: MiniAppID
    public let destination: String?
}

/// Opens a registered Feature's root. Links never execute Feature operations.
public enum MiniAppLink {
    /// The Feature interprets this opaque identifier and validates its existence.
    public static func url(for id: MiniAppID, destination: String) -> URL? {
        guard isValidDestination(destination), let root = url(for: id),
              var components = URLComponents(url: root, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [URLQueryItem(name: "destination", value: destination)]
        return components.url
    }

    public static func resolveRoute(_ url: URL, registeredIDs: Set<MiniAppID>) -> MiniAppRoute? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var destination: String?
        if components.query != nil {
            guard let items = components.queryItems, items.count == 1,
                  items[0].name == "destination", let value = items[0].value,
                  isValidDestination(value) else { return nil }
            destination = value
        }
        components.query = nil
        guard let root = components.url, let id = resolve(root, registeredIDs: registeredIDs) else { return nil }
        return MiniAppRoute(id: id, destination: destination)
    }

    private static func isValidDestination(_ value: String) -> Bool {
        !value.isEmpty && value.rangeOfCharacter(from: .controlCharacters) == nil
    }

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
