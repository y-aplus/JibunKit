import Foundation
import XCTest
import JibunKitCore

final class MiniAppHTTPIsolationTests: XCTestCase, @unchecked Sendable {
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
        for cookie in configurations[0].httpCookieStorage?.cookies ?? [] {
            configurations[0].httpCookieStorage?.deleteCookie(cookie)
        }
        let (remainingCookie, _) = try await sessions[1].data(for: request("/echo", owner: "b"))
        XCTAssertEqual(String(decoding: remainingCookie, as: UTF8.self), "account=b")
        var remainingCache = try request(path, owner: "network-fallback")
        remainingCache.cachePolicy = .returnCacheDataDontLoad
        let (data, _) = try await sessions[1].data(for: remainingCache)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "b")
    }
}
