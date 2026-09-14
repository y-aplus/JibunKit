#if os(iOS)
import Foundation
import Network
import XCTest

@MainActor
final class P1DeviceHTTPFixtureTests: XCTestCase {
    func testConcurrentStartupAndCacheHeaders() async throws {
        async let a = P1DeviceHTTPFixture.shared.start()
        async let b = P1DeviceHTTPFixture.shared.start()
        let first = try await a
        let second = try await b
        XCTAssertEqual(first, second)
        let base = try await P1DeviceHTTPFixture.shared.start()
        var request = URLRequest(url: base.appendingPathComponent("cache/fixture"))
        request.setValue("fixture", forHTTPHeaderField: "X-Fixture-Owner")
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "fixture")
        XCTAssertEqual((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Cache-Control"), "max-age=3600")
    }

    func testAwaitStartBeforeHoldThenReleaseCompletesOnce() async throws {
        let base = try await P1DeviceHTTPFixture.shared.start()
        let token = "fixture-" + UUID().uuidString
        async let waiting = URLSession.shared.data(from: base.appendingPathComponent("await-start/" + token))
        try await Task.sleep(for: .milliseconds(50))
        let hold = URLSession.shared.dataTask(with: base.appendingPathComponent("hold/" + token)); hold.resume()
        let (_, waitResponse) = try await waiting
        XCTAssertEqual((waitResponse as? HTTPURLResponse)?.statusCode, 200)
        let (_, release) = try await URLSession.shared.data(from: base.appendingPathComponent("release/" + token))
        XCTAssertEqual((release as? HTTPURLResponse)?.statusCode, 200)
    }
}
#endif
