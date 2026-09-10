import Foundation
import XCTest
import JibunKitCore

final class MiniAppCookieStoreTests: XCTestCase {
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
