#if canImport(Security)
import Foundation

/// One live owner per Feature/profile. Persists only cookies with an absolute
/// expiry, in the Feature's Keychain namespace. HTTP credential storage is separate.
@MainActor
public final class MiniAppCookieStore {
    public enum Failure: Error, Equatable { case invalidArchive, unsupportedVersion, unsupportedCookie }
    public let storage: HTTPCookieStorage
    private let keychain: MiniAppKeychain
    private let account: String

    public init(context: MiniAppContext, profile: String = "default") throws {
        let configuration = URLSessionConfiguration.ephemeral
        guard let storage = configuration.httpCookieStorage else { throw Failure.unsupportedCookie }
        self.storage = storage
        keychain = MiniAppKeychain(context: context, service: "network-cookies-v1")
        account = profile
        try reload()
    }

    /// Call after receiving responses and before declaring login/logout durable.
    /// Stop in-flight writers first when taking a shutdown/logout snapshot.
    public func save(now: Date = .now) throws {
        var entries: [[String: Any]] = []
        for cookie in storage.cookies ?? [] where !cookie.isSessionOnly {
            guard let expiry = cookie.expiresDate else { throw Failure.unsupportedCookie }
            guard expiry > now else { continue }
            guard let original = cookie.properties else { throw Failure.unsupportedCookie }
            var properties = Dictionary(uniqueKeysWithValues: original.map { ($0.key.rawValue, $0.value) })
            // Do not restart a relative Max-Age when reconstructing a later session.
            properties.removeValue(forKey: HTTPCookiePropertyKey.maximumAge.rawValue)
            properties[HTTPCookiePropertyKey.expires.rawValue] = expiry
            for (key, value) in properties {
                if let url = value as? URL { properties[key] = url.absoluteString }
            }
            guard PropertyListSerialization.propertyList(properties, isValidFor: .binary) else { throw Failure.unsupportedCookie }
            // Encoding a property list alone does not prove Foundation can restore
            // it without changing the cookie's routing, protection, or lifetime.
            let restored = try Self.decode(properties, now: now, failure: .unsupportedCookie)
            guard let restored,
                  restored.name == cookie.name, restored.value == cookie.value,
                  restored.domain == cookie.domain, restored.path == cookie.path,
                  restored.isSecure == cookie.isSecure, restored.isHTTPOnly == cookie.isHTTPOnly,
                  restored.version == cookie.version, restored.portList == cookie.portList else {
                throw Failure.unsupportedCookie
            }
            entries.append(properties)
        }
        let archive: [String: Any] = ["version": 1, "cookies": entries]
        let data = try PropertyListSerialization.data(fromPropertyList: archive, format: .binary, options: 0)
        try keychain.set(data, for: account)
    }

    /// Validate completely before changing the live store. Do not call while
    /// requests are running: reloading replaces this profile's in-memory cookies.
    public func reload(now: Date = .now) throws {
        var cookies: [HTTPCookie] = []
        if let data = try keychain.data(for: account) {
            guard let archive = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let version = archive["version"] as? Int else { throw Failure.invalidArchive }
            guard version == 1 else { throw Failure.unsupportedVersion }
            guard let entries = archive["cookies"] as? [[String: Any]] else { throw Failure.invalidArchive }
            for entry in entries {
                if let cookie = try Self.decode(entry, now: now, failure: .invalidArchive) { cookies.append(cookie) }
            }
        }
        for cookie in storage.cookies ?? [] { storage.deleteCookie(cookie) }
        for cookie in cookies { storage.setCookie(cookie) }
    }

    private static func decode(_ entry: [String: Any], now: Date, failure: Failure) throws -> HTTPCookie? {
        guard let expiry = entry[HTTPCookiePropertyKey.expires.rawValue] as? Date,
              expiry.timeIntervalSince1970.isFinite,
              // Version 1 of our archive stores absolute lifetimes only. A
              // relative lifetime here could extend a login on each reload.
              entry[HTTPCookiePropertyKey.maximumAge.rawValue] == nil else { throw failure }
        guard expiry > now else { return nil }
        let properties = Dictionary(uniqueKeysWithValues: entry.map { (HTTPCookiePropertyKey(rawValue: $0.key), $0.value) })
        guard let cookie = HTTPCookie(properties: properties), !cookie.isSessionOnly,
              let actualExpiry = cookie.expiresDate,
              abs(actualExpiry.timeIntervalSince(expiry)) < 1 else { throw failure }
        return cookie
    }

    /// Quiesce requests first so a late response cannot log this profile back in.
    /// Persistent deletion must succeed before clearing the live store.
    public func clear() throws {
        try keychain.remove(account: account)
        for cookie in storage.cookies ?? [] { storage.deleteCookie(cookie) }
    }
}
#endif
