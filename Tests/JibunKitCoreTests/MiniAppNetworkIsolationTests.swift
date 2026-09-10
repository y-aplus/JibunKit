import Foundation
import XCTest

/// Native baseline: ephemeral isolation is useful but is not persistent Feature networking.
final class MiniAppNetworkIsolationTests: XCTestCase {
    func testNativeEphemeralStoresIsolateSameServerIdentityAndRemoval() throws {
        let first = URLSessionConfiguration.ephemeral
        let second = URLSessionConfiguration.ephemeral
        let a = try XCTUnwrap(first.httpCookieStorage)
        let b = try XCTUnwrap(second.httpCookieStorage)
        XCTAssertFalse(a === b)
        XCTAssertFalse(a === HTTPCookieStorage.shared)
        let domain = "jibunkit-isolation.example"
        func cookie(_ value: String) throws -> HTTPCookie {
            try XCTUnwrap(HTTPCookie(properties: [.domain: domain, .path: "/", .name: "account", .value: value]))
        }
        a.setCookie(try cookie("a"))
        b.setCookie(try cookie("b"))
        XCTAssertEqual(a.cookies?.first(where: { $0.name == "account" })?.value, "a")
        XCTAssertEqual(b.cookies?.first(where: { $0.name == "account" })?.value, "b")
        for item in a.cookies ?? [] { a.deleteCookie(item) }
        XCTAssertTrue(a.cookies?.isEmpty ?? true)
        XCTAssertEqual(b.cookies?.first(where: { $0.name == "account" })?.value, "b")

        let credentialsA = try XCTUnwrap(first.urlCredentialStorage)
        let credentialsB = try XCTUnwrap(second.urlCredentialStorage)
        XCTAssertFalse(credentialsA === credentialsB)
        XCTAssertFalse(credentialsA === URLCredentialStorage.shared)
        let protection = URLProtectionSpace(host: domain, port: 443, protocol: "https", realm: "same", authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
        let credentialA = URLCredential(user: "account", password: "a", persistence: .forSession)
        let credentialB = URLCredential(user: "account", password: "b", persistence: .forSession)
        credentialsA.setDefaultCredential(credentialA, for: protection)
        credentialsB.setDefaultCredential(credentialB, for: protection)
        XCTAssertEqual(credentialsA.defaultCredential(for: protection)?.password, "a")
        XCTAssertEqual(credentialsB.defaultCredential(for: protection)?.password, "b")
        credentialsA.remove(credentialA, for: protection)
        XCTAssertNil(credentialsA.defaultCredential(for: protection))
        XCTAssertEqual(credentialsB.defaultCredential(for: protection)?.password, "b")

        let cacheA = try XCTUnwrap(first.urlCache)
        let cacheB = try XCTUnwrap(second.urlCache)
        XCTAssertFalse(cacheA === cacheB)
        let url = try XCTUnwrap(URL(string: "https://\(domain)/same"))
        let request = URLRequest(url: url)
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Cache-Control": "max-age=3600"]))
        cacheA.storeCachedResponse(CachedURLResponse(response: response, data: Data("a".utf8)), for: request)
        cacheB.storeCachedResponse(CachedURLResponse(response: response, data: Data("b".utf8)), for: request)
        XCTAssertEqual(cacheA.cachedResponse(for: request)?.data, Data("a".utf8))
        cacheA.removeAllCachedResponses()
        XCTAssertNil(cacheA.cachedResponse(for: request))
        XCTAssertEqual(cacheB.cachedResponse(for: request)?.data, Data("b".utf8))
    }

    func testDefaultCookieStoreIsSharedSoSeparateSessionsAloneAreInsufficient() {
        let first = URLSessionConfiguration.default
        let second = URLSessionConfiguration.default
        XCTAssertTrue(first.httpCookieStorage === second.httpCookieStorage)
        XCTAssertTrue(first.httpCookieStorage === HTTPCookieStorage.shared)
    }
}
