import Foundation
import XCTest
@testable import JibunKitCore

final class MiniAppLinkTests: XCTestCase {
    func testNotificationDestinationPreservesLegacyRootAndOpaqueID() throws {
        let context = MiniAppContext(id: MiniAppID("records"))
        let legacy = try XCTUnwrap(MiniAppNotificationRoute.candidateRoute(userInfo: context.notificationUserInfo))
        XCTAssertEqual(legacy.id, context.id)
        XCTAssertNil(legacy.destination)
        let destination = UUID().uuidString
        let info = try XCTUnwrap(context.notificationUserInfo(destination: destination))
        XCTAssertEqual(MiniAppNotificationRoute.candidateRoute(userInfo: info)?.destination, destination)
        XCTAssertEqual(MiniAppNotificationRoute.candidate(userInfo: info), context.id)
        XCTAssertNil(context.notificationUserInfo(destination: ""))
        for value in [42, "", "bad\nvalue"] as [Any] {
            var invalid: [AnyHashable: Any] = context.notificationUserInfo
            invalid[MiniAppNotificationRoute.destinationUserInfoKey] = value
            XCTAssertNil(MiniAppNotificationRoute.candidateRoute(userInfo: invalid))
        }
    }

    func testDestinationRoundTripPreservesFeatureOwnedIdentifiers() throws {
        let id = MiniAppID("records")
        for destination in [UUID().uuidString, "日本語/詳細?x=1&y=2", "a+b%20#c"] {
            let url = try XCTUnwrap(MiniAppLink.url(for: id, destination: destination))
            let route = try XCTUnwrap(MiniAppLink.resolveRoute(url, registeredIDs: [id]))
            XCTAssertEqual(route.id, id)
            XCTAssertEqual(route.destination, destination)
            XCTAssertNil(MiniAppLink.resolveRoute(url, registeredIDs: []))
            XCTAssertNil(MiniAppLink.resolve(url, registeredIDs: [id]), "Legacy root-only resolver remains strict")
        }
        let root = try XCTUnwrap(MiniAppLink.url(for: id))
        XCTAssertNil(try XCTUnwrap(MiniAppLink.resolveRoute(root, registeredIDs: [id])).destination)
    }

    func testRejectsAmbiguousDestinationQueries() throws {
        let id = MiniAppID("records")
        for query in ["", "destination", "destination=", "destination=a&destination=b",
                      "destination=a&delete=true", "delete=true", "destination=%00", "destination=a%0Ab"] {
            let url = try XCTUnwrap(URL(string: "jibunkit://mini-app/records?" + query))
            XCTAssertNil(MiniAppLink.resolveRoute(url, registeredIDs: [id]), query)
        }
        XCTAssertNil(MiniAppLink.url(for: id, destination: ""))
        XCTAssertNil(MiniAppLink.url(for: id, destination: "a\nb"))
        XCTAssertNil(MiniAppLink.url(for: MiniAppID("../records"), destination: "a"))
        let foreign = try XCTUnwrap(URL(string: "https://mini-app/records?destination=a"))
        XCTAssertNil(MiniAppLink.resolveRoute(foreign, registeredIDs: [id]))
    }

    func testRoundTripForRegisteredFeatures() throws {
        for value in ["counter", "reminder", "org.example.notes-2_v1"] {
            let id = MiniAppID(value)
            let url = try XCTUnwrap(MiniAppLink.url(for: id))
            XCTAssertEqual(url.absoluteString, "jibunkit://mini-app/\(value)")
            XCTAssertEqual(MiniAppLink.resolve(url, registeredIDs: [id]), id)
            XCTAssertNil(MiniAppLink.resolve(url, registeredIDs: []))
        }
        XCTAssertNil(MiniAppLink.url(for: MiniAppID("../counter")))
    }

    func testRejectsUnsupportedAndAmbiguousLinks() throws {
        for value in [
            "https://mini-app/counter", "jibunkit://other/counter",
            "jibunkit://mini-app/", "jibunkit://mini-app/Counter",
            "jibunkit://mini-app/counter/", "jibunkit://mini-app/counter/detail",
            "jibunkit://mini-app/counter?delete=true", "jibunkit://mini-app/counter#detail",
            "jibunkit://user@mini-app/counter", "jibunkit://mini-app:80/counter",
            "jibunkit://mini-app/%2Fcounter", "jibunkit://mini-app/%252Fcounter",
            "jibunkit://mini-app/missing",
        ] {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertNil(MiniAppLink.resolve(url, registeredIDs: [MiniAppID("counter")]), value)
        }
    }
}
