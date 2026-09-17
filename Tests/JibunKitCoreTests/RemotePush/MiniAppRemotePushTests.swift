import XCTest
@testable import JibunKitCore

@MainActor
final class MiniAppRemotePushTests: XCTestCase {
    private let a = MiniAppID("push-a")
    private let b = MiniAppID("push-b")

    func testAppTokenFansOutWithSeparateServerIdentityAndChangedToken() async throws {
        let coordinator = MiniAppRemotePushCoordinator()
        let log = PushLog()
        let sa = try service(a, "server-a", coordinator, log)
        let sb = try service(b, "server-b", coordinator, log)
        let ra = MiniAppRuntime(), rb = MiniAppRuntime()
        try await sa.connect(to: ra); try await sb.connect(to: rb)
        await coordinator.didRegisterForRemoteNotifications(deviceToken: Data([1]))
        await coordinator.didRegisterForRemoteNotifications(deviceToken: Data([1]))
        await coordinator.didRegisterForRemoteNotifications(deviceToken: Data([2]))
        XCTAssertEqual(log.tokens[a], [Data([1]), Data([2])])
        XCTAssertEqual(log.tokens[b], [Data([1]), Data([2])])
        XCTAssertEqual(log.servers[a], ["server-a", "server-a"])
        XCTAssertEqual(log.servers[b], ["server-b", "server-b"])
        await ra.shutdown(); await rb.shutdown()
    }

    func testRegistrationFailureIsScopedToCurrentConnectedGenerations() async throws {
        let coordinator = MiniAppRemotePushCoordinator(); let log = PushLog()
        let runtime = MiniAppRuntime(); try await service(a, "a", coordinator, log).connect(to: runtime)
        await coordinator.didFailToRegisterForRemoteNotifications(PushTestError.rejected)
        XCTAssertEqual(log.failures[a]?.count, 1)
        await runtime.shutdown()
        await coordinator.didFailToRegisterForRemoteNotifications(PushTestError.rejected)
        XCTAssertEqual(log.failures[a]?.count, 1)
    }

    func testOwnerOnlyDeliveryDoesNotBroadcast() async throws {
        let coordinator = MiniAppRemotePushCoordinator(); let log = PushLog()
        let ra = MiniAppRuntime(), rb = MiniAppRuntime()
        try await service(a, "a", coordinator, log).connect(to: ra)
        try await service(b, "b", coordinator, log).connect(to: rb)
        let result = await coordinator.deliver(userInfo: [
            MiniAppNotificationRoute.miniAppIDUserInfoKey: a.rawValue,
            MiniAppNotificationRoute.destinationUserInfoKey: "inbox", "value": 7,
            "aps": ["content-available": 1]])
        XCTAssertEqual(result, .newData)
        XCTAssertEqual(log.messages[a]?.map(\.destination), ["inbox"])
        XCTAssertNil(log.messages[b])
        XCTAssertEqual(log.messages[a]?.first?.userInfo["value"], "7")
        let fullPayload = try XCTUnwrap(log.messages[a]?.first).propertyListUserInfo()
        XCTAssertEqual((fullPayload["aps"] as? [String: Int])?["content-available"], 1)
        let unowned = await coordinator.deliver(userInfo: ["value": "no owner"])
        XCTAssertEqual(unowned, .noData)
        await ra.shutdown(); await rb.shutdown()
    }

    func testStopAndLateOldGenerationCleanupCannotRemoveReplacement() async throws {
        let coordinator = MiniAppRemotePushCoordinator(); let log = PushLog()
        let old = MiniAppRuntime(), replacement = MiniAppRuntime()
        let service = try service(a, "a", coordinator, log)
        try await service.connect(to: old)
        await old.shutdown()
        try await service.connect(to: replacement)
        await old.shutdown() // idempotent late join
        let replacementResult = await coordinator.deliver(userInfo: [MiniAppNotificationRoute.miniAppIDUserInfoKey: a.rawValue])
        XCTAssertEqual(replacementResult, .newData)
        XCTAssertEqual(log.messages[a]?.count, 1)
        await replacement.shutdown()
        let stoppedResult = await coordinator.deliver(userInfo: [MiniAppNotificationRoute.miniAppIDUserInfoKey: a.rawValue])
        XCTAssertEqual(stoppedResult, .noData)
    }

    func testUnregisterOnlyRemovesOwnerAndPreservesOtherState() async throws {
        let coordinator = MiniAppRemotePushCoordinator(); let log = PushLog()
        let sa = try service(a, "a", coordinator, log), sb = try service(b, "b", coordinator, log)
        let ra = MiniAppRuntime(), rb = MiniAppRuntime()
        try await sa.connect(to: ra); try await sb.connect(to: rb)
        await sa.unregister()
        XCTAssertEqual(log.unregistered[a], ["a"])
        let resultA = await coordinator.deliver(userInfo: [MiniAppNotificationRoute.miniAppIDUserInfoKey: a.rawValue])
        let resultB = await coordinator.deliver(userInfo: [MiniAppNotificationRoute.miniAppIDUserInfoKey: b.rawValue])
        XCTAssertEqual(resultA, .noData)
        XCTAssertEqual(resultB, .newData)
        await ra.shutdown(); await rb.shutdown()
    }

    func testCompletionAggregatorCombinesPrecedenceAndCompletesOnce() async {
        let completed = expectation(description: "completed")
        completed.expectedFulfillmentCount = 1
        let values = LockedResults()
        let aggregator = MiniAppRemotePushCompletionAggregator { value in values.append(value); completed.fulfill() }
        let a = aggregator.ticket(), b = aggregator.ticket(), c = aggregator.ticket()
        aggregator.finishAdding()
        b(.newData); a(.noData); a(.failed); c(.failed)
        await fulfillment(of: [completed], timeout: 2)
        XCTAssertEqual(values.values, [.failed])
    }

    private func service(_ owner: MiniAppID, _ server: String, _ coordinator: MiniAppRemotePushCoordinator,
                         _ log: PushLog) throws -> MiniAppRemotePushService {
        let identity = try MiniAppRemotePushIdentity(server: server, account: "shared-local-id")
        return MiniAppRemotePushService(owner: owner, identity: identity, coordinator: coordinator,
            onRegistration: { event in log.record(owner, event) },
            onDelivery: { message in log.messages[owner, default: []].append(message); return .newData })
    }
}

private enum PushTestError: Error { case rejected }

@MainActor
private final class PushLog {
    var tokens: [MiniAppID: [Data]] = [:]
    var servers: [MiniAppID: [String]] = [:]
    var failures: [MiniAppID: [String]] = [:]
    var unregistered: [MiniAppID: [String]] = [:]
    var messages: [MiniAppID: [MiniAppRemotePushMessage]] = [:]
    func record(_ owner: MiniAppID, _ event: MiniAppRemotePushRegistrationEvent) {
        switch event {
        case .tokenChanged(let token, let identity, _):
            tokens[owner, default: []].append(token); servers[owner, default: []].append(identity.server)
        case .registrationFailed(let message, _): failures[owner, default: []].append(message)
        case .ownerUnregistered(let identity): unregistered[owner, default: []].append(identity.server)
        }
    }
}

private final class LockedResults: @unchecked Sendable {
    private let lock = NSLock(); private var storage: [MiniAppRemotePushFetchResult] = []
    var values: [MiniAppRemotePushFetchResult] { lock.lock(); defer { lock.unlock() }; return storage }
    func append(_ value: MiniAppRemotePushFetchResult) { lock.lock(); storage.append(value); lock.unlock() }
}
