#if canImport(UserNotifications)
import Foundation
import UserNotifications
import XCTest
@testable import JibunKitCore

@MainActor
final class MiniAppNotificationRequestSnapshotTests: XCTestCase {
    func testNativeRequestRoundTripPreservesPayloadContentAndTrigger() async throws {
        let content = UNMutableNotificationContent()
        content.title = "title"
        content.subtitle = "subtitle"
        content.body = "本文"
        content.categoryIdentifier = "category"
        content.threadIdentifier = "thread"
        content.badge = 7
        content.userInfo = ["record": ["id": 42, "flags": [true, false]], "bytes": Data([0, 1, 255])]
        let request = UNNotificationRequest(identifier: "request", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: true))
        let snapshot = try MiniAppNotificationRequestSnapshot(request: request)
        let transferred = await Task.detached { snapshot }.value
        let restored = try transferred.request()
        XCTAssertEqual(restored.identifier, "request")
        XCTAssertEqual(restored.content.title, "title")
        XCTAssertEqual(restored.content.subtitle, "subtitle")
        XCTAssertEqual(restored.content.body, "本文")
        XCTAssertEqual(restored.content.categoryIdentifier, "category")
        XCTAssertEqual(restored.content.threadIdentifier, "thread")
        XCTAssertEqual(restored.content.badge, 7)
        XCTAssertTrue(NSDictionary(dictionary: restored.content.userInfo).isEqual(to: content.userInfo))
        let trigger = try XCTUnwrap(restored.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(trigger.timeInterval, 60)
        XCTAssertTrue(trigger.repeats)
    }

    func testSourceMutationAndOneReadCannotChangeLaterReads() throws {
        let nested = NSMutableDictionary(dictionary: ["value": "original"])
        let content = UNMutableNotificationContent()
        content.userInfo = ["nested": nested]
        let snapshot = try MiniAppNotificationRequestSnapshot(request:
            UNNotificationRequest(identifier: "a", content: content, trigger: nil))
        nested["value"] = "changed"
        let first = try snapshot.request()
        let editable = try XCTUnwrap(first.content.mutableCopy() as? UNMutableNotificationContent)
        editable.userInfo = ["different": "value"]
        let second = try snapshot.request()
        XCTAssertFalse(first === second)
        XCTAssertEqual((second.content.userInfo["nested"] as? [String: String])?["value"], "original")
        XCTAssertNil(second.trigger)
    }

    @MainActor
    func testActionDeliveryRetainsOnlySelectedOwnersNativePayload() async throws {
        let owner = MiniAppID("owner")
        let content = UNMutableNotificationContent()
        content.userInfo = ["record": "owner-private-record"]
        let snapshot = try MiniAppNotificationRequestSnapshot(request:
            UNNotificationRequest(identifier: "owned", content: content, trigger: nil))
        let action = MiniAppNotificationAction(kind: .custom("reply"), requestIdentifier: "owned",
            destination: nil, userText: "reply text", requestSnapshot: snapshot)
        var deliveries = 0
        await MiniAppNotificationActionDelivery.deliver(action,
            route: MiniAppRoute(id: owner, destination: nil), handlerForOwner: { selected in
                XCTAssertEqual(selected, owner)
                return { event in
                    deliveries += 1
                    do {
                        let request = try XCTUnwrap(event.requestSnapshot).request()
                        XCTAssertEqual(request.content.userInfo["record"] as? String, "owner-private-record")
                        XCTAssertEqual(event.userText, "reply text")
                    } catch { XCTFail("Native snapshot lost: \(error)") }
                }
            }, open: { _ in XCTFail("Custom action must not navigate") })
        XCTAssertEqual(deliveries, 1)
    }
}
#endif
