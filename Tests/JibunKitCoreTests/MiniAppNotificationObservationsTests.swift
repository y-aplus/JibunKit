import Foundation
import XCTest
import JibunKitCore

final class MiniAppNotificationObservationsTests: XCTestCase, @unchecked Sendable {
    @MainActor
    func testCancellingOneOwnerLeavesOtherOwnerSubscribed() async throws {
        let center = NotificationCenter()
        let name = Notification.Name("owned-observation")
        let first = MiniAppNotificationObservations()
        let second = MiniAppNotificationObservations()
        let received = ObservationValues()

        try first.observe(center: center, name: name, extract: intValue) {
            received.first.append($0)
        }
        try second.observe(center: center, name: name, extract: intValue) {
            received.second.append($0)
        }

        center.post(name: name, object: nil, userInfo: ["value": 1])
        await drainMainActor()
        first.cancelAll()
        center.post(name: name, object: nil, userInfo: ["value": 2])
        await drainMainActor()

        XCTAssertEqual(received.first, [1])
        XCTAssertEqual(received.second, [1, 2])
    }

    @MainActor
    func testUsesNativeNameAndObjectFiltering() async throws {
        let center = NotificationCenter()
        let wantedName = Notification.Name("wanted")
        let otherName = Notification.Name("other")
        let wantedSender = NSObject()
        let otherSender = NSObject()
        let observations = MiniAppNotificationObservations()
        let received = ObservationValues()

        try observations.observe(
            center: center,
            name: wantedName,
            object: wantedSender,
            extract: intValue
        ) { received.first.append($0) }

        center.post(name: otherName, object: wantedSender, userInfo: ["value": 1])
        center.post(name: wantedName, object: otherSender, userInfo: ["value": 2])
        center.post(name: wantedName, object: wantedSender, userInfo: ["value": 3])
        await drainMainActor()

        XCTAssertEqual(received.first, [3])
    }

    @MainActor
    func testCancellationSuppressesDeliveryAlreadyQueuedToMainActor() async throws {
        let center = NotificationCenter()
        let name = Notification.Name("queued")
        let observations = MiniAppNotificationObservations()
        let received = ObservationValues()

        try observations.observe(center: center, name: name, extract: { notification in
            return notification.userInfo?["value"] as? Int
        }) { received.first.append($0) }

        center.post(name: name, object: nil, userInfo: ["value": 1])
        observations.cancelAll()
        await drainMainActor()

        XCTAssertTrue(received.first.isEmpty)
        XCTAssertThrowsError(try observations.observe(center: center, name: name, extract: intValue) { _ in })
    }

    @MainActor
    func testIndividualCancellationReleasesReceiverWhileOwnerRemainsAlive() throws {
        let center = NotificationCenter()
        let observations = MiniAppNotificationObservations()
        weak var releasedReceiver: ReceiverProbe?

        do {
            let receiver = ReceiverProbe()
            releasedReceiver = receiver
            let observation = try observations.observe(
                center: center,
                name: Notification.Name("individual-cancellation"),
                extract: intValue
            ) { [receiver] value in
                receiver.values.append(value)
            }

            observation.cancel()
        }

        XCTAssertNil(releasedReceiver)
        XCTAssertFalse(observations.isCancelled)
    }

    @MainActor
    func testReleasingOwnerRemovesNativeObserverAndReceiver() async throws {
        let center = NotificationCenter()
        let name = Notification.Name("released-owner")
        weak var releasedReceiver: ReceiverProbe?
        var observations: MiniAppNotificationObservations? = MiniAppNotificationObservations()

        do {
            let receiver = ReceiverProbe()
            releasedReceiver = receiver
            try observations?.observe(center: center, name: name, extract: intValue) { [receiver] value in
                receiver.values.append(value)
            }
        }

        observations = nil
        XCTAssertNil(releasedReceiver)

        center.post(name: name, object: nil, userInfo: ["value": 1])
        await drainMainActor()
        XCTAssertNil(releasedReceiver)
    }

    @MainActor
    func testReentrantPostIsDeliveredInOrder() async throws {
        let center = NotificationCenter()
        let name = Notification.Name("reentrant")
        let observations = MiniAppNotificationObservations()
        let received = ObservationValues()

        try observations.observe(center: center, name: name, extract: intValue) { value in
            received.first.append(value)
            if value == 1 {
                center.post(name: name, object: nil, userInfo: ["value": 2])
            }
        }

        center.post(name: name, object: nil, userInfo: ["value": 1])
        await drainMainActor()

        XCTAssertEqual(received.first, [1, 2])
    }

    @MainActor
    func testRuntimeShutdownRemovesObserversBeforeReturning() async throws {
        let center = NotificationCenter()
        let name = Notification.Name("runtime-owned")
        let runtime = MiniAppRuntime()
        let otherRuntime = MiniAppRuntime()
        let observations = try runtime.makeNotificationObservations()
        let otherObservations = try otherRuntime.makeNotificationObservations()
        let received = ObservationValues()

        try observations.observe(center: center, name: name, extract: intValue) {
            received.first.append($0)
        }
        try otherObservations.observe(center: center, name: name, extract: intValue) {
            received.second.append($0)
        }

        await runtime.shutdown()
        center.post(name: name, object: nil, userInfo: ["value": 1])
        await drainMainActor()

        XCTAssertTrue(received.first.isEmpty)
        XCTAssertEqual(received.second, [1])
        await otherRuntime.shutdown()
    }

    func testBackgroundPostExtractsBeforeMainActorDelivery() async throws {
        let center = NotificationCenter()
        let name = Notification.Name("background")
        let extractedOffMain = LockedBoolean()
        let delivered = expectation(description: "delivered")
        let observations = await MainActor.run { MiniAppNotificationObservations() }

        try await observations.observe(center: center, name: name, extract: { notification in
            extractedOffMain.value = !Thread.isMainThread
            return notification.userInfo?["value"] as? Int
        }) { value in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(value, 7)
            delivered.fulfill()
        }

        await Task.detached {
            center.post(name: name, object: nil, userInfo: ["value": 7])
        }.value
        await fulfillment(of: [delivered], timeout: 5)

        XCTAssertTrue(extractedOffMain.value)
        await observations.cancelAll()
    }
}

private let intValue: @Sendable (Notification) -> Int? = {
    $0.userInfo?["value"] as? Int
}

@MainActor
private final class ObservationValues {
    var first: [Int] = []
    var second: [Int] = []
}

@MainActor
private final class ReceiverProbe {
    var values: [Int] = []
}

private final class LockedBoolean: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false
    var value: Bool {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }
}

@MainActor
private func drainMainActor() async {
    for _ in 0..<4 { await Task.yield() }
}
