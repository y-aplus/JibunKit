import Foundation
import XCTest
import JibunKitCore

final class MiniAppHTTPIsolationTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testPersistentProfilesSendOnlyTheirOwnLoginAndLogoutIndependently() async throws {
        guard let port = ProcessInfo.processInfo.environment["JIBUNKIT_NETWORK_TEST_PORT"] else {
            throw XCTSkip("Loopback HTTP fixture required")
        }
        let context = MiniAppContext(id: MiniAppID("http-profiles"))
        let prefix = UUID().uuidString
        let profiles = [prefix + "/account", prefix + "/../account", prefix + "/日本語"]
        let stores = try profiles.map { try MiniAppCookieStore(context: context, profile: $0) }
        defer { stores.forEach { try? $0.clear() } }
        func session(_ store: MiniAppCookieStore) -> URLSession {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = store.storage
            return URLSession(configuration: config)
        }
        func url(_ path: String) throws -> URL { try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/\(path)")) }
        let original = stores.map(session)
        defer { original.forEach { $0.invalidateAndCancel() } }
        for index in stores.indices {
            var login = URLRequest(url: try url("set-persistent"))
            login.setValue("profile-\(index)", forHTTPHeaderField: "X-Fixture-Owner")
            _ = try await original[index].data(for: login)
            try stores[index].save()
            original[index].finishTasksAndInvalidate()
        }
        let reopened = try profiles.map { try MiniAppCookieStore(context: context, profile: $0) }
        let sessions = reopened.map(session)
        defer { sessions.forEach { $0.invalidateAndCancel() } }
        for index in sessions.indices {
            let (data, _) = try await sessions[index].data(from: url("redirect"))
            XCTAssertEqual(String(decoding: data, as: UTF8.self), "account=profile-\(index)")
        }
        _ = try await sessions[0].data(from: url("logout"))
        try reopened[0].save()
        // A local logout and a server logout both remain scoped to one profile.
        try reopened[1].clear()
        for index in sessions.indices {
            let persisted = try MiniAppCookieStore(context: context, profile: profiles[index])
            let check = session(persisted)
            defer { check.invalidateAndCancel() }
            let (data, _) = try await check.data(from: url("echo"))
            XCTAssertEqual(String(decoding: data, as: UTF8.self), index == 2 ? "account=profile-2" : "")
        }
    }

    @MainActor
    func testPersistentCookiesSurviveSessionRecreationAndServerLogout() async throws {
        guard let port = ProcessInfo.processInfo.environment["JIBUNKIT_NETWORK_TEST_PORT"] else {
            throw XCTSkip("Loopback HTTP fixture required")
        }
        let context = MiniAppContext(id: MiniAppID("http-persistent"))
        let profile = UUID().uuidString
        let cookies = try MiniAppCookieStore(context: context, profile: profile)
        defer { try? cookies.clear() }
        func session(_ store: MiniAppCookieStore) -> URLSession {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = store.storage
            return URLSession(configuration: config)
        }
        func url(_ path: String) throws -> URL { try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/\(path)")) }
        let first = session(cookies)
        defer { first.invalidateAndCancel() }
        var login = URLRequest(url: try url("set-persistent"))
        login.setValue("persistent", forHTTPHeaderField: "X-Fixture-Owner")
        _ = try await first.data(for: login)
        try cookies.save()
        let reopened = try MiniAppCookieStore(context: context, profile: profile)
        let second = session(reopened)
        defer { second.invalidateAndCancel() }
        let (data, _) = try await second.data(from: url("echo"))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "account=persistent")
        _ = try await second.data(from: url("logout"))
        try reopened.save()
        let loggedOut = try MiniAppCookieStore(context: context, profile: profile)
        XCTAssertTrue(loggedOut.storage.cookies?.isEmpty ?? true)
    }

    func testActualRequestsKeepCookiesAndCachedResponsesOwned() async throws {
        guard let port = ProcessInfo.processInfo.environment["JIBUNKIT_NETWORK_TEST_PORT"] else {
            throw XCTSkip("Start Tests/Fixtures/network_server.py and set JIBUNKIT_NETWORK_TEST_PORT")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let configurations = try ["a", "b"].map { id in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = try MiniAppContext(id: MiniAppID(id)).urlCache(
                memoryCapacity: 1048576, diskCapacity: 1048576, containerURL: root)
            return configuration
        }
        let sessions = configurations.map { URLSession(configuration: $0) }
        defer { sessions.forEach { $0.invalidateAndCancel() } }
        func request(_ path: String, owner: String) throws -> URLRequest {
            let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)\(path)"))
            var request = URLRequest(url: url)
            request.setValue(owner, forHTTPHeaderField: "X-Fixture-Owner")
            return request
        }
        for (index, owner) in ["a", "b"].enumerated() {
            _ = try await sessions[index].data(for: request("/set", owner: owner))
        }
        for (index, owner) in ["a", "b"].enumerated() {
            let (data, _) = try await sessions[index].data(for: request("/echo", owner: owner))
            XCTAssertEqual(String(decoding: data, as: UTF8.self), "account=\(owner)")
            let (redirected, _) = try await sessions[index].data(for: request("/redirect", owner: owner))
            XCTAssertEqual(String(decoding: redirected, as: UTF8.self), "account=\(owner)")
        }
        let path = "/cache/" + UUID().uuidString
        for (index, owner) in ["a", "b"].enumerated() {
            let (data, _) = try await sessions[index].data(for: request(path, owner: owner))
            XCTAssertEqual(String(decoding: data, as: UTF8.self), owner)
        }
        for (index, owner) in ["a", "b"].enumerated() {
            var cached = try request(path, owner: "network-fallback")
            cached.cachePolicy = .returnCacheDataDontLoad
            let (data, _) = try await sessions[index].data(for: cached)
            XCTAssertEqual(String(decoding: data, as: UTF8.self), owner)
        }
        configurations[0].urlCache?.removeAllCachedResponses()
        _ = try await sessions[0].data(for: request("/logout", owner: "a"))
        let (removedCookie, _) = try await sessions[0].data(for: request("/echo", owner: "a"))
        XCTAssertEqual(String(decoding: removedCookie, as: UTF8.self), "")
        let (remainingCookie, _) = try await sessions[1].data(for: request("/echo", owner: "b"))
        XCTAssertEqual(String(decoding: remainingCookie, as: UTF8.self), "account=b")
        var remainingCache = try request(path, owner: "network-fallback")
        remainingCache.cachePolicy = .returnCacheDataDontLoad
        let (data, _) = try await sessions[1].data(for: remainingCache)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "b")
    }

    func testHTTPAuthenticationChallengesUseOnlyTheirSessionCredentials() async throws {
        guard let rawPort = ProcessInfo.processInfo.environment["JIBUNKIT_NETWORK_TEST_PORT"], let port = Int(rawPort) else {
            throw XCTSkip("Loopback HTTP fixture required")
        }
        let space = URLProtectionSpace(host: "127.0.0.1", port: port, protocol: "http", realm: "same", authenticationMethod: NSURLAuthenticationMethodHTTPBasic)
        let sessions = ["a", "b"].map { password in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCredentialStorage?.setDefaultCredential(
                URLCredential(user: "account", password: password, persistence: .forSession), for: space)
            return URLSession(configuration: configuration)
        }
        defer { sessions.forEach { $0.invalidateAndCancel() } }
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/auth"))
        for (index, password) in ["a", "b"].enumerated() {
            let (data, response) = try await sessions[index].data(from: url)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            XCTAssertEqual(String(decoding: data, as: UTF8.self), "Basic " + Data("account:\(password)".utf8).base64EncodedString())
        }
    }
}
