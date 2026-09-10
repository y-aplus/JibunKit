import Foundation
import XCTest
import JibunKitCore

final class MiniAppURLSessionLifetimeTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testRuntimeCancelsOwnedRequestThenClearsLoginWithoutAffectingOtherSession() async throws {
        guard let port = ProcessInfo.processInfo.environment["JIBUNKIT_NETWORK_TEST_PORT"] else {
            throw XCTSkip("Loopback HTTP fixture required")
        }
        let context = MiniAppContext(id: MiniAppID("http-cancel"))
        let profile = UUID().uuidString
        let cookies = try MiniAppCookieStore(context: context, profile: profile)
        defer { try? cookies.clear() }
        cookies.storage.setCookie(try XCTUnwrap(HTTPCookie(properties: [
            .domain: "127.0.0.1", .path: "/", .name: "account", .value: "old-login",
            .expires: Date.now.addingTimeInterval(3600)
        ])))
        try cookies.save()
        let lifetime = MiniAppURLSessionLifetime()
        let gate = SessionCleanupGate()
        await gate.release()
        let invalidated = expectation(description: "Cancelled session invalidated")
        let cancelled = expectation(description: "Owned HTTP request cancelled")
        let delegate = LifetimeTestDelegate(lifetime: lifetime, gate: gate, entered: invalidated)
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = cookies.storage
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        let other = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel(); other.invalidateAndCancel() }
        let token = UUID().uuidString
        func url(_ path: String) throws -> URL { try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/\(path)")) }
        let heldURL = try url("hold/\(token)")
        let runtime = MiniAppRuntime()
        let outcome = LifetimeOutcome()
        try runtime.onShutdownAsync {
            do {
                try await lifetime.finishAndWait(session)
                try cookies.clear()
            } catch { outcome.error = error }
        }
        try runtime.start {
            do { _ = try await session.data(from: heldURL); XCTFail("Held request must be cancelled") }
            catch { XCTAssertEqual((error as? URLError)?.code, .cancelled) }
            cancelled.fulfill()
        }
        let (_, started) = try await other.data(from: url("await-start/\(token)"))
        XCTAssertEqual((started as? HTTPURLResponse)?.statusCode, 200)
        let ended = expectation(description: "Cancellation shutdown completed")
        let shutdown = Task { await runtime.shutdown(); outcome.returned = true; ended.fulfill() }
        await fulfillment(of: [ended], timeout: 10)
        guard outcome.returned else { shutdown.cancel(); return }
        await fulfillment(of: [cancelled, invalidated], timeout: 5)
        XCTAssertNil(outcome.error)
        _ = try await other.data(from: url("release/\(token)"))
        let (_, response) = try await other.data(from: url("echo"))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let reopened = try MiniAppCookieStore(context: context, profile: profile)
        XCTAssertTrue(reopened.storage.cookies?.isEmpty ?? true)
        XCTAssertTrue(cookies.storage.cookies?.isEmpty ?? true)
    }

    @MainActor
    func testRuntimeWaitsForHTTPAndDelegateCleanupBeforeSavingCookies() async throws {
        guard let port = ProcessInfo.processInfo.environment["JIBUNKIT_NETWORK_TEST_PORT"] else {
            throw XCTSkip("Loopback HTTP fixture required")
        }
        let context = MiniAppContext(id: MiniAppID("http-lifetime"))
        let profile = UUID().uuidString
        let cookies = try MiniAppCookieStore(context: context, profile: profile)
        defer { try? cookies.clear() }
        let lifetime = MiniAppURLSessionLifetime()
        let gate = SessionCleanupGate()
        let callbackEntered = expectation(description: "Native invalidation delivered")
        let responseCompleted = expectation(description: "Held response completed")
        let delegate = LifetimeTestDelegate(lifetime: lifetime, gate: gate, entered: callbackEntered)
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = cookies.storage
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        let other = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel(); other.invalidateAndCancel() }
        let token = UUID().uuidString
        func url(_ path: String) throws -> URL { try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/\(path)")) }
        let request = session.dataTask(with: try url("hold/\(token)")) { _, response, error in
            XCTAssertNil(error)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            responseCompleted.fulfill()
        }
        request.resume()
        let (_, started) = try await other.data(from: url("await-start/\(token)"))
        XCTAssertEqual((started as? HTTPURLResponse)?.statusCode, 200)
        let runtime = MiniAppRuntime()
        let outcome = LifetimeOutcome()
        let shutdownEnded = expectation(description: "Graceful shutdown completed")
        try runtime.onShutdownAsync {
            do {
                try await lifetime.finishAndWait(session)
                try cookies.save()
                outcome.saved = true
            } catch { outcome.error = error }
        }
        let shuttingDown = Task { await runtime.shutdown(); outcome.returned = true; shutdownEnded.fulfill() }
        // Another owner's session remains usable while this response is held.
        let (_, otherResponse) = try await other.data(from: url("echo"))
        XCTAssertEqual((otherResponse as? HTTPURLResponse)?.statusCode, 200)
        let (_, release) = try await other.data(from: url("release/\(token)"))
        XCTAssertEqual((release as? HTTPURLResponse)?.statusCode, 200)
        await fulfillment(of: [responseCompleted, callbackEntered], timeout: 5)
        XCTAssertTrue(runtime.isClosed)
        XCTAssertThrowsError(try runtime.start {})
        XCTAssertFalse(outcome.saved)
        XCTAssertFalse(outcome.returned)
        let beforeCleanup = try MiniAppCookieStore(context: context, profile: profile)
        XCTAssertTrue(beforeCleanup.storage.cookies?.isEmpty ?? true)
        let joining = Task { try await lifetime.finishAndWait(session) }
        joining.cancel() // Cancellation must not masquerade as completed cleanup.
        await gate.release()
        await fulfillment(of: [shutdownEnded], timeout: 10)
        guard outcome.returned else { shuttingDown.cancel(); joining.cancel(); return }
        await shuttingDown.value
        try await joining.value
        XCTAssertNil(outcome.error)
        XCTAssertTrue(outcome.saved)
        XCTAssertTrue(outcome.returned)
        let afterCleanup = try MiniAppCookieStore(context: context, profile: profile)
        XCTAssertEqual(afterCleanup.storage.cookies?.first?.value, "late-response")
        // A later waiter sees the same completed boundary without a new callback.
        try await lifetime.finishAndWait(session)
    }

    func testEarlyErrorDuplicateCallbackAndWrongSessionAreHandled() async throws {
        let lifetime = MiniAppURLSessionLifetime()
        let first = URLSession(configuration: .ephemeral)
        let other = URLSession(configuration: .ephemeral)
        defer { first.invalidateAndCancel(); other.invalidateAndCancel() }
        let error = URLError(.networkConnectionLost)
        let accepted = await lifetime.didBecomeInvalid(first, error: error)
        XCTAssertTrue(accepted)
        let duplicate = await lifetime.didBecomeInvalid(first, error: nil)
        let unrelated = await lifetime.didBecomeInvalid(other, error: nil)
        XCTAssertFalse(duplicate)
        XCTAssertFalse(unrelated)
        for _ in 0..<2 {
            do { try await lifetime.finishAndWait(first); XCTFail("Must retain the invalidation error") }
            catch { XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost) }
        }
        do { try await lifetime.finishAndWait(other); XCTFail("Must not bind a second session") }
        catch { XCTAssertEqual(error as? MiniAppURLSessionLifetime.Failure, .differentSession) }
        do { try await MiniAppURLSessionLifetime().finishAndWait(.shared); XCTFail("Shared sessions cannot invalidate") }
        catch { XCTAssertEqual(error as? MiniAppURLSessionLifetime.Failure, .sharedSession) }
    }
}

private final class LifetimeTestDelegate: NSObject, URLSessionDelegate, Sendable {
    let lifetime: MiniAppURLSessionLifetime
    let gate: SessionCleanupGate
    let entered: XCTestExpectation

    init(lifetime: MiniAppURLSessionLifetime, gate: SessionCleanupGate, entered: XCTestExpectation) {
        self.lifetime = lifetime
        self.gate = gate
        self.entered = entered
    }

    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        Task {
            entered.fulfill()
            await gate.wait()
            await lifetime.didBecomeInvalid(session, error: error)
        }
    }
}

private actor SessionCleanupGate {
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor private final class LifetimeOutcome {
    var saved = false
    var returned = false
    var error: Error?
}
