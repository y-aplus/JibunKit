import Foundation
import XCTest
@testable import JibunKitCore

@MainActor
final class MiniAppWebAuthenticationTests: XCTestCase {
    func testPresentationConflictReportsCurrentOwnerAndDoesNotCreateSecondSession() throws {
        let coordinator = MiniAppWebAuthenticationCoordinator()
        let provider = WebAuthenticationProviderSpy()
        let a = MiniAppWebAuthentication(context: context("feature-a"), coordinator: coordinator, provider: provider)
        let b = MiniAppWebAuthentication(context: context("feature-b"), coordinator: coordinator, provider: provider)
        let request = try a.start(url: authURL, callbackURLScheme: "a") { _ in }

        XCTAssertEqual(coordinator.activeOwner, MiniAppID("feature-a"))
        XCTAssertThrowsError(try b.start(url: authURL, callbackURLScheme: "b") { _ in }) { error in
            XCTAssertEqual(error as? MiniAppWebAuthenticationCoordinator.Failure,
                           .presentationBusy(owner: MiniAppID("feature-a")))
        }
        XCTAssertEqual(provider.sessions.count, 1)
        withExtendedLifetime(request) {}
    }

    func testCompletionReturnsOnlyToStartingFeatureAndReleasesPresentation() throws {
        let coordinator = MiniAppWebAuthenticationCoordinator()
        let provider = WebAuthenticationProviderSpy()
        let a = MiniAppWebAuthentication(context: context("feature-a"), coordinator: coordinator, provider: provider)
        let b = MiniAppWebAuthentication(context: context("feature-b"), coordinator: coordinator, provider: provider)
        var aCallbacks: [URL] = []
        var bCallbacks: [URL] = []
        let aRequest = try a.start(url: authURL, callbackURLScheme: "a") {
            if case let .success(url) = $0 { aCallbacks.append(url) }
        }
        let aCallback = URL(string: "a://callback?code=one")!
        provider.sessions[0].complete(.success(aCallback))

        XCTAssertTrue(aRequest.isFinished)
        XCTAssertEqual(aCallbacks, [aCallback])
        XCTAssertTrue(bCallbacks.isEmpty)
        let bRequest = try b.start(url: authURL, callbackURLScheme: "b") {
            if case let .success(url) = $0 { bCallbacks.append(url) }
        }
        let bCallback = URL(string: "b://callback?code=two")!
        provider.sessions[1].complete(.success(bCallback))
        provider.sessions[0].complete(.success(URL(string: "a://late")!))

        XCTAssertTrue(bRequest.isFinished)
        XCTAssertEqual(aCallbacks, [aCallback])
        XCTAssertEqual(bCallbacks, [bCallback])
        XCTAssertNil(coordinator.activeOwner)
    }

    func testOwnedCancellationIsIdempotentAndLateNativeCompletionIsIgnored() throws {
        let coordinator = MiniAppWebAuthenticationCoordinator()
        let provider = WebAuthenticationProviderSpy()
        let authentication = MiniAppWebAuthentication(
            context: context("feature-a"), coordinator: coordinator, provider: provider)
        var results: [Result<URL, Error>] = []
        let request = try authentication.start(url: authURL, callbackURLScheme: "a") {
            results.append($0)
        }

        request.cancel()
        request.cancel()
        provider.sessions[0].complete(.success(URL(string: "a://late")!))

        XCTAssertTrue(request.isFinished)
        XCTAssertEqual(provider.sessions[0].cancelCount, 1)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].failure as? MiniAppWebAuthenticationCoordinator.Failure, .cancelled)
        XCTAssertNil(coordinator.activeOwner)
    }

    func testRejectedStartCompletesItsOwnerAndAllowsOtherFeature() throws {
        let coordinator = MiniAppWebAuthenticationCoordinator()
        let provider = WebAuthenticationProviderSpy(startResults: [false, true])
        let a = MiniAppWebAuthentication(context: context("feature-a"), coordinator: coordinator, provider: provider)
        let b = MiniAppWebAuthentication(context: context("feature-b"), coordinator: coordinator, provider: provider)
        var failure: Error?
        let rejected = try a.start(url: authURL, callbackURLScheme: "a") {
            if case let .failure(error) = $0 { failure = error }
        }

        XCTAssertTrue(rejected.isFinished)
        XCTAssertEqual(failure as? MiniAppWebAuthenticationCoordinator.Failure, .startRejected)
        XCTAssertNil(coordinator.activeOwner)
        let admitted = try b.start(url: authURL, callbackURLScheme: "b") { _ in }
        XCTAssertEqual(coordinator.activeOwner, MiniAppID("feature-b"))
        withExtendedLifetime(admitted) {}
    }

    func testRuntimeShutdownCancelsOnlyItsFeaturesRequest() async throws {
        let coordinator = MiniAppWebAuthenticationCoordinator()
        let provider = WebAuthenticationProviderSpy()
        let runtimeA = MiniAppRuntime()
        let runtimeB = MiniAppRuntime()
        let a = try runtimeA.makeWebAuthentication(
            context: context("feature-a"), coordinator: coordinator, provider: provider)
        let b = try runtimeB.makeWebAuthentication(
            context: context("feature-b"), coordinator: coordinator, provider: provider)
        var aFailure: Error?
        let request = try a.start(url: authURL, callbackURLScheme: "a") {
            if case let .failure(error) = $0 { aFailure = error }
        }

        await runtimeB.shutdown()
        XCTAssertFalse(request.isFinished)
        XCTAssertEqual(provider.sessions[0].cancelCount, 0)
        await runtimeA.shutdown()
        XCTAssertTrue(request.isFinished)
        XCTAssertEqual(provider.sessions[0].cancelCount, 1)
        XCTAssertEqual(aFailure as? MiniAppWebAuthenticationCoordinator.Failure, .cancelled)
        XCTAssertThrowsError(try a.start(url: authURL, callbackURLScheme: "a") { _ in })
        XCTAssertThrowsError(try b.start(url: authURL, callbackURLScheme: "b") { _ in })
    }

    func testOldConnectionCannotCancelNewConnectionForSameFeature() async throws {
        let coordinator = MiniAppWebAuthenticationCoordinator()
        let provider = WebAuthenticationProviderSpy()
        let oldRuntime = MiniAppRuntime()
        let newRuntime = MiniAppRuntime()
        let old = try oldRuntime.makeWebAuthentication(
            context: context("feature-a"), coordinator: coordinator, provider: provider)
        let replacement = try newRuntime.makeWebAuthentication(
            context: context("feature-a"), coordinator: coordinator, provider: provider)
        var replacementCallbacks = 0
        let oldRequest = try old.start(url: authURL, callbackURLScheme: "a") { _ in }
        provider.sessions[0].complete(.success(URL(string: "a://old")!))
        let replacementRequest = try replacement.start(
            url: authURL, callbackURLScheme: "a") { _ in replacementCallbacks += 1 }

        old.cancel()
        await oldRuntime.shutdown()
        provider.sessions[0].complete(.success(URL(string: "a://old-late")!))

        XCTAssertTrue(oldRequest.isFinished)
        XCTAssertFalse(replacementRequest.isFinished)
        XCTAssertEqual(provider.sessions[1].cancelCount, 0)
        XCTAssertEqual(coordinator.activeOwner, MiniAppID("feature-a"))
        provider.sessions[1].complete(.success(URL(string: "a://replacement")!))
        XCTAssertEqual(replacementCallbacks, 1)
        await newRuntime.shutdown()
    }

    func testSeparatePresentationCoordinatorsDoNotConflict() throws {
        let provider = WebAuthenticationProviderSpy()
        let firstCoordinator = MiniAppWebAuthenticationCoordinator()
        let secondCoordinator = MiniAppWebAuthenticationCoordinator()
        let first = MiniAppWebAuthentication(
            context: context("feature-a"), coordinator: firstCoordinator, provider: provider)
        let second = MiniAppWebAuthentication(
            context: context("feature-b"), coordinator: secondCoordinator, provider: provider)

        let firstRequest = try first.start(url: authURL, callbackURLScheme: "a") { _ in }
        let secondRequest = try second.start(url: authURL, callbackURLScheme: "b") { _ in }

        XCTAssertEqual(provider.sessions.count, 2)
        XCTAssertEqual(firstCoordinator.activeOwner, MiniAppID("feature-a"))
        XCTAssertEqual(secondCoordinator.activeOwner, MiniAppID("feature-b"))
        withExtendedLifetime((firstRequest, secondRequest)) {}
    }

    private var authURL: URL { URL(string: "https://example.invalid/authorize")! }
    private func context(_ id: String) -> MiniAppContext { MiniAppContext(id: MiniAppID(id)) }
}

private extension Result {
    var failure: Failure? {
        guard case let .failure(error) = self else { return nil }
        return error
    }
}

@MainActor
private final class WebAuthenticationProviderSpy: MiniAppWebAuthenticationSessionProviding {
    var sessions: [WebAuthenticationSessionSpy] = []
    private var startResults: [Bool]

    init(startResults: [Bool] = []) { self.startResults = startResults }

    func makeSession(
        url: URL,
        callbackURLScheme: String?,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) -> any MiniAppWebAuthenticationSession {
        let result = startResults.isEmpty ? true : startResults.removeFirst()
        let session = WebAuthenticationSessionSpy(
            url: url, callbackURLScheme: callbackURLScheme,
            startResult: result, completion: completion)
        sessions.append(session)
        return session
    }
}

@MainActor
private final class WebAuthenticationSessionSpy: MiniAppWebAuthenticationSession {
    let url: URL
    let callbackURLScheme: String?
    let startResult: Bool
    let completion: @MainActor (Result<URL, Error>) -> Void
    var startCount = 0
    var cancelCount = 0

    init(
        url: URL,
        callbackURLScheme: String?,
        startResult: Bool,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) {
        self.url = url
        self.callbackURLScheme = callbackURLScheme
        self.startResult = startResult
        self.completion = completion
    }

    func start() -> Bool { startCount += 1; return startResult }
    func cancel() { cancelCount += 1 }
    func complete(_ result: Result<URL, Error>) { completion(result) }
}
