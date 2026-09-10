import Foundation
import XCTest
@testable import JibunKitCore

@MainActor
final class MiniAppURLRouterTests: XCTestCase {
    func testSameSchemeRoutesToUniqueOwnerAndPreservesOriginalURL() throws {
        let url = try XCTUnwrap(URL(string: "https://example.test/a/item?q=a%2Bb&x=1#part"))
        var received: [URL] = []
        let registrations: [MiniAppURLRouter.Registration] = [
            .init(id: MiniAppID("a")) { value in
                received.append(value)
                return value.host == "example.test" && value.path.hasPrefix("/a/") ? .detail("opaque/日本語") : nil
            },
            .init(id: MiniAppID("b")) { value in
                received.append(value)
                return value.host == "example.test" && value.path.hasPrefix("/b/") ? .root : nil
            },
        ]
        let route = try XCTUnwrap(MiniAppURLRouter.resolve(url, registrations: registrations))
        XCTAssertEqual(route.id, MiniAppID("a"))
        XCTAssertEqual(route.destination, "opaque/日本語")
        XCTAssertEqual(received, [url, url])
        let b = try XCTUnwrap(MiniAppURLRouter.resolve(URL(string: "https://example.test/b/home")!, registrations: registrations))
        XCTAssertEqual(b.id, MiniAppID("b"))
        XCTAssertNil(b.destination)
        XCTAssertNil(try MiniAppURLRouter.resolve(URL(string: "https://foreign.test/a/item")!, registrations: registrations))
    }

    func testAmbiguousOwnersRejectRegardlessOfRegistrationOrder() throws {
        let url = try XCTUnwrap(URL(string: "example://shared"))
        let registrations: [MiniAppURLRouter.Registration] = [
            .init(id: MiniAppID("b")) { _ in .root },
            .init(id: MiniAppID("a")) { _ in .detail("item") },
        ]
        for ordered in [registrations, Array(registrations.reversed())] {
            XCTAssertThrowsError(try MiniAppURLRouter.resolve(url, registrations: ordered)) {
                XCTAssertEqual($0 as? MiniAppURLRouter.Failure, .ambiguousOwners([MiniAppID("a"), MiniAppID("b")]))
            }
        }
    }

    func testInvalidRegistrationsFailBeforeInvokingAnyResolver() throws {
        let url = URL(string: "example://item")!
        var calls = 0
        let valid = MiniAppURLRouter.Registration(id: MiniAppID("a")) { _ in calls += 1; return .root }
        let invalid = MiniAppURLRouter.Registration(id: MiniAppID("../a")) { _ in calls += 1; return .root }
        XCTAssertThrowsError(try MiniAppURLRouter.resolve(url, registrations: [valid, invalid])) {
            XCTAssertEqual($0 as? MiniAppURLRouter.Failure, .invalidOwner(MiniAppID("../a")))
        }
        XCTAssertThrowsError(try MiniAppURLRouter.resolve(url, registrations: [valid, valid])) {
            XCTAssertEqual($0 as? MiniAppURLRouter.Failure, .duplicateOwner(MiniAppID("a")))
        }
        XCTAssertEqual(calls, 0)
    }

    func testReservedHostAndRelativeURLsNeverReachFeatureResolvers() throws {
        var calls = 0
        let registrations = [MiniAppURLRouter.Registration(id: MiniAppID("a")) { _ in calls += 1; return .root }]
        for address in ["jibunkit://mini-app/a", "JiBuNkIt://mini-app/a?delete=true", "relative/path"] {
            XCTAssertNil(try MiniAppURLRouter.resolve(URL(string: address)!, registrations: registrations))
        }
        XCTAssertEqual(calls, 0)
    }
}
