#if canImport(UserNotifications)
import Foundation
import XCTest
import UserNotifications
import RecordsFeature
import JibunKitCore
import RecordsBackupIntegration

final class RecordsNotificationTests: XCTestCase {
    func testMultipleRecordsHaveIndependentRequestsAndDetailRoutes() throws {
        let now = Date(timeIntervalSince1970: 1000)
        let first = Record(title: "First")
        let second = Record(title: "Second")
        let a = try RecordsNotifications.request(for: first, at: now.addingTimeInterval(60), now: now)
        let b = try RecordsNotifications.request(for: second, at: now.addingTimeInterval(120), now: now)
        let replacement = try RecordsNotifications.request(for: first, at: now.addingTimeInterval(180), now: now)
        XCTAssertNotEqual(a.identifier, b.identifier)
        XCTAssertEqual(a.identifier, replacement.identifier)
        XCTAssertEqual((replacement.trigger as? UNTimeIntervalNotificationTrigger)?.timeInterval, 180)
        XCTAssertEqual(a.content.title, first.title)
        for (record, request) in [(first, a), (second, b)] {
            let route = try XCTUnwrap(MiniAppNotificationRoute.candidateRoute(userInfo: request.content.userInfo))
            XCTAssertEqual(route.id, MiniAppID("records"))
            XCTAssertEqual(route.destination, record.id.uuidString)
            XCTAssertFalse(MiniAppContext(id: MiniAppID("reminder")).ownsNotificationRequestIdentifier(request.identifier))
        }
    }

    func testPastAndNonFiniteDatesDoNotProduceRequests() {
        let now = Date(timeIntervalSince1970: 1000)
        for date in [now, now.addingTimeInterval(-1), Date(timeIntervalSince1970: .infinity)] {
            XCTAssertThrowsError(try RecordsNotifications.request(for: Record(title: "Record"), at: date, now: now))
        }
    }
}
#endif
