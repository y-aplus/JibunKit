import Foundation
import XCTest
import JibunKitCore

final class MiniAppCookieStoreTests: XCTestCase {
    @MainActor
    func testInvalidArchivesNeverPartiallyReplaceLiveCookies() throws {
        let context = MiniAppContext(id: MiniAppID("cookie-validation"))
        let profile = UUID().uuidString
        let store = try MiniAppCookieStore(context: context, profile: profile)
        defer { try? store.clear() }
        let keychain = MiniAppKeychain(context: context, service: "network-cookies-v1")
        let expiry = Date.now.addingTimeInterval(3600)
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .domain: "jibunkit.example", .path: "/", .name: "account", .value: "live", .expires: expiry
        ]))
        store.storage.setCookie(cookie)
        try store.save()
        let goodData = try XCTUnwrap(try keychain.data(for: profile))
        let good = try XCTUnwrap(PropertyListSerialization.propertyList(from: goodData, format: nil) as? [String: Any])
        let entries = try XCTUnwrap(good["cookies"] as? [[String: Any]])
        var replacement = try XCTUnwrap(entries.first)
        replacement[HTTPCookiePropertyKey.value.rawValue] = "replacement"
        var relative = replacement
        relative[HTTPCookiePropertyKey.maximumAge.rawValue] = "86400"
        var missingName = replacement
        missingName.removeValue(forKey: HTTPCookiePropertyKey.name.rawValue)
        var missingExpiry = replacement
        missingExpiry.removeValue(forKey: HTTPCookiePropertyKey.expires.rawValue)
        let cases: [([String: Any], MiniAppCookieStore.Failure)] = [
            (["version": 2, "cookies": entries], .unsupportedVersion),
            (["cookies": entries], .invalidArchive),
            (["version": 1, "cookies": "invalid"], .invalidArchive),
            (["version": 1, "cookies": [replacement, missingName]], .invalidArchive),
            (["version": 1, "cookies": [replacement, missingExpiry]], .invalidArchive),
            (["version": 1, "cookies": [relative]], .invalidArchive)
        ]
        for (archive, expected) in cases {
            let data = try PropertyListSerialization.data(fromPropertyList: archive, format: .binary, options: 0)
            try keychain.set(data, for: profile)
            XCTAssertThrowsError(try store.reload()) { XCTAssertEqual($0 as? MiniAppCookieStore.Failure, expected) }
            XCTAssertEqual(store.storage.cookies?.map(\.value), ["live"])
            XCTAssertEqual(try keychain.data(for: profile), data, "Failed reads must not rewrite saved data")
        }
        try keychain.set(goodData, for: profile)
        try store.reload()
        XCTAssertEqual(store.storage.cookies?.map(\.value), ["live"])
    }

    @MainActor
    func testSavedMaxAgeUsesOriginalAbsoluteExpiryAcrossReloads() throws {
        let context = MiniAppContext(id: MiniAppID("cookie-lifetime"))
        let profile = UUID().uuidString
        let store = try MiniAppCookieStore(context: context, profile: profile)
        defer { try? store.clear() }
        let url = try XCTUnwrap(URL(string: "https://jibunkit.example/account"))
        let cookie = try XCTUnwrap(HTTPCookie.cookies(withResponseHeaderFields: [
            "Set-Cookie": "account=persistent; Path=/account; Max-Age=3600; Secure; HttpOnly"
        ], for: url).first)
        let expiry = try XCTUnwrap(cookie.expiresDate)
        store.storage.setCookie(cookie)
        try store.save()
        for _ in 0..<3 {
            try store.reload(now: expiry.addingTimeInterval(-10))
            let restored = try XCTUnwrap(store.storage.cookies?.first)
            XCTAssertEqual(try XCTUnwrap(restored.expiresDate).timeIntervalSince1970, expiry.timeIntervalSince1970, accuracy: 1)
            XCTAssertTrue(restored.isSecure)
            XCTAssertTrue(restored.isHTTPOnly)
            try store.save()
        }
        try store.reload(now: expiry.addingTimeInterval(1))
        XCTAssertTrue(store.storage.cookies?.isEmpty ?? true)
    }

    @MainActor
    func testPersistenceExpiryLogoutAndCorruptionPreserveOwnership() throws {
        let profile = UUID().uuidString
        let a = MiniAppContext(id: MiniAppID("cookie-a"))
        let b = MiniAppContext(id: MiniAppID("cookie-b"))
        let first = try MiniAppCookieStore(context: a, profile: profile)
        let second = try MiniAppCookieStore(context: b, profile: profile)
        defer { try? first.clear(); try? second.clear() }
        let expiry = Date.now.addingTimeInterval(3600)
        func cookie(_ value: String, persistent: Bool) throws -> HTTPCookie {
            var properties: [HTTPCookiePropertyKey: Any] = [.domain: "jibunkit.example", .path: "/account", .name: persistent ? "login" : "session", .value: value, .secure: "TRUE"]
            if persistent { properties[.expires] = expiry }
            return try XCTUnwrap(HTTPCookie(properties: properties))
        }
        first.storage.setCookie(try cookie("a", persistent: true))
        first.storage.setCookie(try cookie("temporary", persistent: false))
        second.storage.setCookie(try cookie("b", persistent: true))
        try first.save()
        try second.save()
        let reopened = try MiniAppCookieStore(context: a, profile: profile)
        XCTAssertEqual(reopened.storage.cookies?.count, 1)
        let restored = try XCTUnwrap(reopened.storage.cookies?.first)
        XCTAssertEqual(restored.value, "a")
        XCTAssertEqual(restored.path, "/account")
        XCTAssertTrue(restored.isSecure)
        XCTAssertEqual(try XCTUnwrap(restored.expiresDate).timeIntervalSince1970, expiry.timeIntervalSince1970, accuracy: 1)
        try reopened.reload(now: expiry.addingTimeInterval(1))
        XCTAssertTrue(reopened.storage.cookies?.isEmpty ?? true)
        try reopened.reload()
        let keychain = MiniAppKeychain(context: a, service: "network-cookies-v1")
        try keychain.set(Data("broken".utf8), for: profile)
        XCTAssertThrowsError(try reopened.reload())
        XCTAssertEqual(reopened.storage.cookies?.first?.value, "a")
        try reopened.clear()
        let loggedOut = try MiniAppCookieStore(context: a, profile: profile)
        XCTAssertTrue(loggedOut.storage.cookies?.isEmpty ?? true)
        let other = try MiniAppCookieStore(context: b, profile: profile)
        XCTAssertEqual(other.storage.cookies?.first?.value, "b")
    }
}
