#if os(iOS)
import Foundation
import Network
import XCTest

@MainActor
final class P1DeviceHTTPFixtureTests: XCTestCase {
    func testConcurrentStartupAndRealCacheAndHTMLResponses() async throws {
        let server = P1DeviceHTTPFixture(port: 0)
        defer { server.stop() }
        async let a = server.start()
        async let b = server.start()
        let first = try await a
        let second = try await b
        XCTAssertEqual(first, second)
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = URLCache(memoryCapacity: 1_048_576, diskCapacity: 0)
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: first.appendingPathComponent("cache/fixture"))
        request.setValue("fixture", forHTTPHeaderField: "X-Fixture-Owner")
        let (data, response) = try await session.data(for: request)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "fixture")
        XCTAssertEqual((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Cache-Control"), "max-age=3600")
        request.cachePolicy = .returnCacheDataDontLoad
        request.setValue("must-not-reach-network", forHTTPHeaderField: "X-Fixture-Owner")
        let (cached, _) = try await session.data(for: request)
        XCTAssertEqual(cached, data)
        let (page, html) = try await session.data(from: first.appendingPathComponent("complete"))
        XCTAssertTrue(String(decoding: page, as: UTF8.self).contains("jibunkit-auth-probe://callback?code=local"))
        XCTAssertEqual((html as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type"), "text/html; charset=utf-8")
    }

    func testAwaitBeforeHoldDuplicateRejectionAndReleasedResponse() async throws {
        let server = P1DeviceHTTPFixture(port: 0)
        defer { server.stop() }
        let base = try await server.start()
        let waiting = Task { try await request(base, "await-start/order") }
        try await waitUntil { server.waitingRequestCount == 1 }
        let hold = Task { try await request(base, "hold/order") }
        let acknowledgement = try await waiting.value
        XCTAssertEqual(acknowledgement.statusCode, 200)
        let duplicate = try await request(base, "hold/order")
        XCTAssertEqual(duplicate.statusCode, 409)
        let release = try await request(base, "release/order")
        XCTAssertEqual(release.statusCode, 200)
        let held = try await hold.value
        XCTAssertEqual(held.statusCode, 200)
        XCTAssertTrue(held.value(forHTTPHeaderField: "Set-Cookie")?.contains("late-response") == true)
        let again = try await request(base, "release/order")
        XCTAssertEqual(again.statusCode, 200)
        try await waitUntil { server.liveConnectionCount == 0 }
    }

    func testReleaseBeforeHoldAndGateCapacity() async throws {
        let server = P1DeviceHTTPFixture(port: 0)
        defer { server.stop() }
        let base = try await server.start()
        let release = try await request(base, "release/early")
        XCTAssertEqual(release.statusCode, 200)
        let held = try await request(base, "hold/early")
        XCTAssertEqual(held.statusCode, 200)
        let started = try await request(base, "await-start/early")
        XCTAssertEqual(started.statusCode, 200)
        for index in 1..<32 {
            let response = try await request(base, "release/token-\(index)")
            XCTAssertEqual(response.statusCode, 200)
        }
        let excess = try await request(base, "release/overflow")
        XCTAssertEqual(excess.statusCode, 429)
    }

    func testIdleWaiterAndHeldRequestExpireAndListenerRemainsUsable() async throws {
        let server = P1DeviceHTTPFixture(port: 0, gateTimeout: .milliseconds(150))
        defer { server.stop() }
        let base = try await server.start()
        let waiter = try await request(base, "await-start/never-started")
        XCTAssertEqual(waiter.statusCode, 504)
        let held = try await request(base, "hold/never-released")
        XCTAssertEqual(held.statusCode, 504)
        let healthy = try await request(base, "echo")
        XCTAssertEqual(healthy.statusCode, 200)
        try await waitUntil { server.liveConnectionCount == 0 }
    }

    func testMalformedDuplicateOversizedEOFAndHeaderDeadlineCleanUp() async throws {
        let server = P1DeviceHTTPFixture(port: 0, headerTimeout: .milliseconds(200))
        defer { server.stop() }
        let base = try await server.start()
        for header in ["Host: localhost\r\nHost: duplicate", "broken", "Transfer-Encoding: chunked"] {
            let response = try await raw(base, "GET /echo HTTP/1.1\r\n\(header)\r\n\r\n")
            XCTAssertTrue(response.hasPrefix("HTTP/1.1 400 "), response)
        }
        let oversized = try await raw(base, "GET /echo HTTP/1.1\r\nX-Large: " + String(repeating: "a", count: 17_000) + "\r\n\r\n")
        XCTAssertTrue(oversized.hasPrefix("HTTP/1.1 431 "), oversized)
        let eof = try await raw(base, "GET /echo HTTP/1.1\r\nHost:", halfClose: true)
        XCTAssertTrue(eof.hasPrefix("HTTP/1.1 400 "), eof)
        let deadline = try await raw(base, "GET /echo HTTP/1.1\r\nHost:")
        XCTAssertTrue(deadline.hasPrefix("HTTP/1.1 408 "), deadline)
        let healthy = try await request(base, "echo")
        XCTAssertEqual(healthy.statusCode, 200)
        try await waitUntil { server.liveConnectionCount == 0 }
    }

    func testStoppedListenerCanRestartWithoutReusingStartupCompletion() async throws {
        let server = P1DeviceHTTPFixture(port: 0)
        defer { server.stop() }
        _ = try await server.start()
        server.stop()
        let restarted = try await server.start()
        let response = try await request(restarted, "echo")
        XCTAssertEqual(response.statusCode, 200)
    }

    private func request(_ base: URL, _ path: String) async throws -> HTTPURLResponse {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (_, response) = try await session.data(from: base.appendingPathComponent(path))
        return try XCTUnwrap(response as? HTTPURLResponse)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(condition())
    }

    // Real TCP, including half-close and incomplete input that URLSession cannot create.
    private func raw(_ base: URL, _ request: String, halfClose: Bool = false) async throws -> String {
        let port = try XCTUnwrap(base.port.flatMap { UInt16(exactly: $0) })
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        connection.start(queue: DispatchQueue(label: "P1DeviceHTTPFixtureTests.client"))
        let timeout = Task {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            connection.cancel()
        }
        defer { timeout.cancel(); connection.cancel() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: Data(request.utf8), contentContext: halfClose ? .finalMessage : .defaultMessage,
                            isComplete: true, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
        var result = Data()
        while true {
            let (data, complete): (Data, Bool) = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 32_768) { data, _, complete, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume(returning: (data ?? Data(), complete)) }
                }
            }
            result.append(data)
            if let end = result.range(of: Data("\r\n\r\n".utf8)) {
                let header = String(decoding: result[..<end.lowerBound], as: UTF8.self)
                let length = header.components(separatedBy: "\r\n").first { $0.hasPrefix("Content-Length: ") }
                    .flatMap { Int($0.dropFirst("Content-Length: ".count)) }
                if let length, result.count >= end.upperBound + length { break }
            }
            if complete { break }
        }
        return String(decoding: result, as: UTF8.self)
    }
}
#endif
