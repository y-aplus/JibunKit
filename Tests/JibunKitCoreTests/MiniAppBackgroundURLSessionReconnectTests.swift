import Foundation
import XCTest
@testable import JibunKitCore

@MainActor
final class MiniAppBackgroundURLSessionReconnectTests: XCTestCase {
    func testIdentifierIsStableReversibleAndSeparatedByOwnerAndProfile() throws {
        let a = context("feature-a")
        let first = try MiniAppBackgroundURLSessionIdentifier(context: a, profile: "signed.in@example")
        let repeated = try MiniAppBackgroundURLSessionIdentifier(context: a, profile: "signed.in@example")
        let otherProfile = try MiniAppBackgroundURLSessionIdentifier(context: a, profile: "別-account")
        let otherOwner = try MiniAppBackgroundURLSessionIdentifier(
            context: context("feature-b"), profile: "signed.in@example")

        XCTAssertEqual(first, repeated)
        XCTAssertNotEqual(first, otherProfile)
        XCTAssertNotEqual(first, otherOwner)
        XCTAssertEqual(try MiniAppBackgroundURLSessionIdentifier(rawValue: first.rawValue), first)
        XCTAssertThrowsError(try MiniAppBackgroundURLSessionIdentifier(context: a, profile: ""))
        XCTAssertThrowsError(try MiniAppBackgroundURLSessionIdentifier(rawValue: "foreign.session"))
    }

    func testFactoriesReconnectWithoutScreenAndNativeDelegateFinishesWarmSessionEvents() async throws {
        let registry = MiniAppBackgroundURLSessionReconnectRegistry()
        let factory = NativeReconnectFixture()
        let completion = CompletionSpy()
        let registration = try registry.register(
            context: context("feature-a"),
            profile: UUID().uuidString,
            reconnect: factory.reconnect
        )

        XCTAssertEqual(
            registry.handleEvents(
                identifier: registration.identifier,
                completionHandler: completion.call
            ),
            .connected
        )
        XCTAssertEqual(factory.identifiers, [registration.identifier])
        XCTAssertEqual(completion.count, 0)
        let firstSession = try XCTUnwrap(factory.session)
        XCTAssertEqual(firstSession.configuration.identifier, registration.identifier)
        factory.delegate.urlSessionDidFinishEvents(forBackgroundURLSession: firstSession)
        for _ in 0..<10 where completion.count == 0 { await Task.yield() }
        XCTAssertEqual(completion.count, 1)

        let warmCompletion = CompletionSpy()
        XCTAssertEqual(registry.handleEvents(
            identifier: registration.identifier,
            completionHandler: warmCompletion.call
        ), .connected)
        XCTAssertTrue(factory.session === firstSession)
        XCTAssertEqual(factory.identifiers, [registration.identifier, registration.identifier])
        factory.delegate.urlSessionDidFinishEvents(forBackgroundURLSession: firstSession)
        for _ in 0..<10 where warmCompletion.count == 0 { await Task.yield() }
        XCTAssertEqual(warmCompletion.count, 1)
        withExtendedLifetime(registration) {}
    }

    func testDuplicateAndDelayedCallbacksCompleteOnceWithoutBlockingNextEvent() throws {
        let registry = MiniAppBackgroundURLSessionReconnectRegistry()
        let factory = ReconnectFactorySpy()
        let firstCompletion = CompletionSpy()
        let duplicateCompletion = CompletionSpy()
        let nextCompletion = CompletionSpy()
        let registration = try registry.register(
            context: context("feature-a"), profile: "primary", reconnect: factory.reconnect)

        XCTAssertEqual(registry.handleEvents(
            identifier: registration.identifier,
            completionHandler: firstCompletion.call
        ), .connected)
        XCTAssertEqual(registry.handleEvents(
            identifier: registration.identifier,
            completionHandler: duplicateCompletion.call
        ), .joinedPending)
        XCTAssertEqual(firstCompletion.count, 0)
        XCTAssertEqual(duplicateCompletion.count, 0)
        XCTAssertEqual(factory.events.count, 1)

        let firstEvents = try XCTUnwrap(factory.events.first)
        XCTAssertTrue(firstEvents.finish())
        XCTAssertFalse(firstEvents.finish())
        XCTAssertEqual(firstCompletion.count, 1)
        XCTAssertEqual(duplicateCompletion.count, 1)

        XCTAssertEqual(registry.handleEvents(
            identifier: registration.identifier,
            completionHandler: nextCompletion.call
        ), .connected)
        XCTAssertEqual(factory.events.count, 2)
        XCTAssertTrue(factory.events[1].finish())
        XCTAssertEqual(nextCompletion.count, 1)
        withExtendedLifetime(registration) {}
    }

    func testCancellingOneOwnerCompletesOnlyItsPendingEvent() throws {
        let registry = MiniAppBackgroundURLSessionReconnectRegistry()
        let aFactory = ReconnectFactorySpy()
        let bFactory = ReconnectFactorySpy()
        let aCompletion = CompletionSpy()
        let bCompletion = CompletionSpy()
        let a = try registry.register(
            context: context("feature-a"), profile: "primary", reconnect: aFactory.reconnect)
        let b = try registry.register(
            context: context("feature-b"), profile: "primary", reconnect: bFactory.reconnect)

        XCTAssertEqual(registry.handleEvents(
            identifier: a.identifier, completionHandler: aCompletion.call), .connected)
        XCTAssertEqual(registry.handleEvents(
            identifier: b.identifier, completionHandler: bCompletion.call), .connected)

        a.cancel()
        a.cancel()
        XCTAssertEqual(aCompletion.count, 0)
        XCTAssertEqual(bCompletion.count, 0)
        XCTAssertTrue(try XCTUnwrap(aFactory.events.first).finish())
        XCTAssertEqual(aCompletion.count, 1)
        XCTAssertTrue(try XCTUnwrap(bFactory.events.first).finish())
        XCTAssertEqual(bCompletion.count, 1)

        let unknownCompletion = CompletionSpy()
        XCTAssertEqual(registry.handleEvents(
            identifier: a.identifier,
            completionHandler: unknownCompletion.call
        ), .unknownSession)
        XCTAssertEqual(unknownCompletion.count, 1)
        withExtendedLifetime(b) {}
    }

    func testOldRegistrationCancellationCannotRemoveReplacementOrFinishNewPendingEvent() async throws {
        let registry = MiniAppBackgroundURLSessionReconnectRegistry()
        let oldFactory = ReconnectFactorySpy()
        let newFactory = ReconnectFactorySpy()
        let oldCompletion = CompletionSpy()
        let newCompletion = CompletionSpy()
        let context = context("feature-a")
        var old: MiniAppBackgroundURLSessionRegistration? = try registry.register(
            context: context, profile: "primary", reconnect: oldFactory.reconnect)
        let identifier = try XCTUnwrap(old?.identifier)
        XCTAssertEqual(registry.handleEvents(
            identifier: identifier, completionHandler: oldCompletion.call), .connected)

        old?.cancel()
        let replacement = try registry.register(
            context: context, profile: "primary", reconnect: newFactory.reconnect)
        old = nil
        await Task.yield()
        XCTAssertEqual(registry.handleEvents(
            identifier: replacement.identifier,
            completionHandler: newCompletion.call
        ), .joinedPending)
        XCTAssertTrue(newFactory.events.isEmpty)
        XCTAssertEqual(oldCompletion.count, 0)
        XCTAssertEqual(newCompletion.count, 0)

        let oldEvents = try XCTUnwrap(oldFactory.events.first)
        XCTAssertTrue(oldEvents.finish())
        XCTAssertFalse(oldEvents.finish())
        XCTAssertEqual(oldCompletion.count, 1)
        XCTAssertEqual(newCompletion.count, 1)

        let nextCompletion = CompletionSpy()
        XCTAssertEqual(registry.handleEvents(
            identifier: replacement.identifier,
            completionHandler: nextCompletion.call
        ), .connected)
        XCTAssertEqual(newFactory.events.count, 1)
        XCTAssertEqual(nextCompletion.count, 0)
        XCTAssertTrue(try XCTUnwrap(newFactory.events.first).finish())
        XCTAssertEqual(nextCompletion.count, 1)
        withExtendedLifetime(replacement) {}
    }

    func testDuplicateRegistrationAndReconnectFailureReleaseCompletions() throws {
        let registry = MiniAppBackgroundURLSessionReconnectRegistry()
        let factory = ReconnectFactorySpy()
        let registration = try registry.register(
            context: context("feature-a"), profile: "primary", reconnect: factory.reconnect)
        XCTAssertThrowsError(try registry.register(
            context: context("feature-a"), profile: "primary", reconnect: factory.reconnect)) {
            XCTAssertEqual(
                $0 as? MiniAppBackgroundURLSessionReconnectRegistry.Failure,
                .duplicateRegistration
            )
        }

        let failingRegistry = MiniAppBackgroundURLSessionReconnectRegistry()
        let completion = CompletionSpy()
        let failing = try failingRegistry.register(
            context: context("feature-b"),
            profile: "primary"
        ) { _, _ in
            throw ReconnectError.failed
        }
        XCTAssertEqual(failingRegistry.handleEvents(
            identifier: failing.identifier,
            completionHandler: completion.call
        ), .reconnectFailed)
        XCTAssertEqual(completion.count, 1)
        withExtendedLifetime((registration, failing)) {}
    }

    private func context(_ id: String) -> MiniAppContext {
        MiniAppContext(id: MiniAppID(id))
    }
}

@MainActor
private final class ReconnectFactorySpy {
    var identifiers: [String] = []
    var events: [MiniAppBackgroundURLSessionEvents] = []

    func reconnect(identifier: String, events: MiniAppBackgroundURLSessionEvents) {
        identifiers.append(identifier)
        self.events.append(events)
    }
}

@MainActor
private final class CompletionSpy {
    private(set) var count = 0
    func call() { count += 1 }
}

@MainActor
private final class NativeReconnectFixture {
    let delegate = NativeReconnectDelegate()
    private(set) var identifiers: [String] = []
    private(set) var session: URLSession?

    func reconnect(identifier: String, events: MiniAppBackgroundURLSessionEvents) {
        identifiers.append(identifier)
        delegate.events = events
        if let session {
            precondition(session.configuration.identifier == identifier)
            return
        }
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
    }
}

private final class NativeReconnectDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    @MainActor var events: MiniAppBackgroundURLSessionEvents?

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            events?.finish()
            events = nil
        }
    }
}

private enum ReconnectError: Error { case failed }
