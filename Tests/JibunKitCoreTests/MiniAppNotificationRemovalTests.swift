import XCTest
import JibunKitCore

final class MiniAppNotificationRemovalTests: XCTestCase {
    func testRemovalKeepsOtherOwnersAndIncludesLegacyAndKeyedRequests() {
        let owner = MiniAppContext(id: MiniAppID("records"))
        let other = MiniAppContext(id: MiniAppID("reminder"))
        let dotted = MiniAppContext(id: MiniAppID("records.child"))
        let prefix = MiniAppContext(id: MiniAppID("records-extra"))
        let first = owner.notificationRequestIdentifier(for: "first")
        let second = owner.notificationRequestIdentifier(for: "second")
        let foreign = [other.notificationRequestIdentifier, dotted.notificationRequestIdentifier,
                       prefix.notificationRequestIdentifier, "external-request"]
        let removal = MiniAppNotificationRemoval(context: owner,
            pending: foreign + [owner.notificationRequestIdentifier, first],
            delivered: [second] + foreign)
        XCTAssertEqual(removal.pending, [owner.notificationRequestIdentifier, first])
        XCTAssertEqual(removal.delivered, [second])
        let untouched = MiniAppNotificationRemoval(context: owner, pending: foreign, delivered: foreign)
        XCTAssertTrue(untouched.pending.isEmpty)
        XCTAssertTrue(untouched.delivered.isEmpty)
    }
}
