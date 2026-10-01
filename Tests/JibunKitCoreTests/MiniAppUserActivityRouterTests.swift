import Foundation
import XCTest
import JibunKitCore

@MainActor
final class MiniAppUserActivityRouterTests: XCTestCase {
    private let a = MiniAppID("a")
    private let b = MiniAppID("b")

    private func registrations() -> [MiniAppUserActivityRouter.Registration] {
        [
            .init(id: a, handler: .init(activityTypes: ["com.example.a.view"]) { activity in
                (activity.userInfo?["id"] as? String).map { MiniAppURLRouter.Destination.detail($0) } ?? .root
            }),
            .init(id: b, handler: .init(activityTypes: ["com.example.b.view"]) { _ in nil }),
        ]
    }

    func testActivityReachesOnlyTheOwnerOfItsType() {
        let activity = NSUserActivity(activityType: "com.example.a.view")
        activity.userInfo = ["id": "note-1"]
        let route = MiniAppUserActivityRouter.route(for: activity, registrations: registrations(), registeredIDs: [a, b])
        XCTAssertEqual(route?.id, a)
        XCTAssertEqual(route?.destination, "note-1")
        activity.userInfo = nil
        XCTAssertNil(MiniAppUserActivityRouter.route(for: activity, registrations: registrations(), registeredIDs: [a, b])?.destination)
        XCTAssertNil(MiniAppUserActivityRouter.route(for: activity, registrations: registrations(), registeredIDs: [b]))
        XCTAssertNil(MiniAppUserActivityRouter.route(for: NSUserActivity(activityType: "com.example.b.view"),
                                                     registrations: registrations(), registeredIDs: [a, b]))
        XCTAssertNil(MiniAppUserActivityRouter.route(for: NSUserActivity(activityType: "unknown"),
                                                     registrations: registrations(), registeredIDs: [a, b]))
        XCTAssertEqual(MiniAppUserActivityRouter.activityTypes(registrations()), ["com.example.a.view", "com.example.b.view"])
    }

    func testTypesMustBeUniqueNonEmptyAndNotHostOwned() {
        let handler = MiniAppUserActivityHandler(activityTypes: ["shared"]) { _ in .root }
        XCTAssertThrowsError(try MiniAppUserActivityRouter.validate([.init(id: a, handler: handler), .init(id: b, handler: handler)],
                                                                    reserved: [])) {
            XCTAssertEqual($0 as? MiniAppUserActivityRouter.Failure, .duplicateType("shared", [a, b]))
        }
        XCTAssertThrowsError(try MiniAppUserActivityRouter.validate([.init(id: a, handler: handler)], reserved: ["shared"])) {
            XCTAssertEqual($0 as? MiniAppUserActivityRouter.Failure, .reservedType("shared"))
        }
        let empty = MiniAppUserActivityHandler(activityTypes: [""]) { _ in .root }
        XCTAssertThrowsError(try MiniAppUserActivityRouter.validate([.init(id: a, handler: empty)], reserved: []))
        XCTAssertNoThrow(try MiniAppUserActivityRouter.validate(registrations(), reserved: ["host"]))
    }
}
