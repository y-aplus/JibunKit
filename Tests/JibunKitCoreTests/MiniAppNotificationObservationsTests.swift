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
        let firstInitial = expectation(description: "first owner receives initial value")
        let secondInitial = expectation(description: "second owner receives initial value")
        let secondAfterCancellation = expectation(description: "second owner remains subscribed")
        let firstAfterCancellation = expectation(description: "cancelled owner stays silent")
        firstAfterCancellation.isInverted = true

        try first.observe(center: center, name: name, extract: intValue) { value in
            received.first.append(value)
            if value == 1 { firstInitial.fulfill() }
            if value == 2 { firstAfterCancellation.fulfill() }
        }
        try second.observe(center: center, name: name, extract: intValue) { value in
            received.second.append(value)
            if value == 1 { secondInitial.fulfill() }
            if value == 2 { secondAfterCancellation.fulfill() }
        }

        center.post(name: name, object: nil, userInfo: ["value": 1])
        await fulfillment(of: [firstInitial, secondInitial], timeout: 1)
        first.cancelAll()
        center.post(name: name, object: nil, userInfo: ["value": 2])
        await fulfillment(of: [secondAfterCancellation, firstAfterCancellation], timeout: 0.1)

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
        let wanted = expectation(description: "matching name and sender delivered")
        let unexpected = expectation(description: "mismatched notification delivered")
        unexpected.isInverted = true

        try observations.observe(
            center: center,
            name: wantedName,
            object: wantedSender,
            extract: intValue
        ) { value in
            received.first.append(value)
            if value == 3 {
                wanted.fulfill()
            } else {
                unexpected.fulfill()
            }
        }

        center.post(name: otherName, object: wantedSender, userInfo: ["value": 1])
        center.post(name: wantedName, object: otherSender, userInfo: ["value": 2])
        center.post(name: wantedName, object: wantedSender, userInfo: ["value": 3])
        await fulfillment(of: [wanted, unexpected], timeout: 0.1)

        XCTAssertEqual(received.first, [3])
    }

    @MainActor
    func testCancellationSuppressesDeliveryAlreadyQueuedToMainActor() async throws {
        let center = NotificationCenter()
        let name = Notification.Name("queued")
        let observations = MiniAppNotificationObservations()
        let received = ObservationValues()
        let delivery = expectation(description: "cancelled queued value delivered")
        delivery.isInverted = true

        try observations.observe(center: center, name: name, extract: { notification in
            return notification.userInfo?["value"] as? Int
        }) {
            received.first.append($0)
            delivery.fulfill()
        }

        center.post(name: name, object: nil, userInfo: ["value": 1])
        observations.cancelAll()
        await fulfillment(of: [delivery], timeout: 0.1)

        XCTAssertTrue(received.first.isEmpty)
        XCTAssertThrowsError(try observations.observe(center: center, name: name, extract: intValue) { _ in })
    }

    @MainActor
    func testRepeatedIndividualCancellationReleasesTokensAndReceiver() throws {
        let center = NotificationCenter()
        let observations = MiniAppNotificationObservations()
        weak var releasedReceiver: ReceiverProbe?
        var releasedObservations: [WeakObservation] = []

        do {
            let receiver = ReceiverProbe()
            releasedReceiver = receiver
            for index in 0..<32 {
                let observation = try observations.observe(
                    center: center,
                    name: Notification.Name("individual-cancellation-\(index)"),
                    extract: intValue
                ) { [receiver] value in
                    receiver.values.append(value)
                }
                releasedObservations.append(WeakObservation(observation))
                observation.cancel()
            }
        }

        XCTAssertNil(releasedReceiver)
        XCTAssertTrue(releasedObservations.allSatisfy { $0.value == nil })
        XCTAssertFalse(observations.isCancelled)
    }

    @MainActor
    func testReleasingOwnerRemovesNativeObserverAndReceiver() async throws {
        let center = NotificationCenter()
        let name = Notification.Name("released-owner")
        weak var releasedReceiver: ReceiverProbe?
        var observations: MiniAppNotificationObservations? = MiniAppNotificationObservations()
        let delivery = expectation(description: "released owner delivered")
        delivery.isInverted = true

        do {
            let receiver = ReceiverProbe()
            releasedReceiver = receiver
            try observations?.observe(center: center, name: name, extract: intValue) { [receiver] value in
                receiver.values.append(value)
                delivery.fulfill()
            }
        }

        observations = nil
        XCTAssertNil(releasedReceiver)

        center.post(name: name, object: nil, userInfo: ["value": 1])
        await fulfillment(of: [delivery], timeout: 0.1)
        XCTAssertNil(releasedReceiver)
    }

    @MainActor
    func testReentrantPostIsDeliveredInOrder() async throws {
        let center = NotificationCenter()
        let name = Notification.Name("reentrant")
        let observations = MiniAppNotificationObservations()
        let received = ObservationValues()
        let delivered = expectation(description: "reentrant values delivered")
        delivered.expectedFulfillmentCount = 2

        try observations.observe(center: center, name: name, extract: intValue) { value in
            received.first.append(value)
            delivered.fulfill()
            if value == 1 {
                center.post(name: name, object: nil, userInfo: ["value": 2])
            }
        }

        center.post(name: name, object: nil, userInfo: ["value": 1])
        await fulfillment(of: [delivered], timeout: 1)

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
        let stoppedRuntimeDelivery = expectation(description: "stopped runtime delivered")
        stoppedRuntimeDelivery.isInverted = true
        let otherRuntimeDelivery = expectation(description: "other runtime delivered")

        try observations.observe(center: center, name: name, extract: intValue) {
            received.first.append($0)
            stoppedRuntimeDelivery.fulfill()
        }
        try otherObservations.observe(center: center, name: name, extract: intValue) {
            received.second.append($0)
            otherRuntimeDelivery.fulfill()
        }

        await runtime.shutdown()
        center.post(name: name, object: nil, userInfo: ["value": 1])
        await fulfillment(of: [otherRuntimeDelivery, stoppedRuntimeDelivery], timeout: 0.1)

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

private final class WeakObservation {
    weak var value: MiniAppNotificationObservation?

    init(_ value: MiniAppNotificationObservation) {
        self.value = value
    }
}

private final class LockedBoolean: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false
    var value: Bool {
        get { lock.withLock { storage } }
        set { lock.withLock { storage = newValue } }
    }
}
