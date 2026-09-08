import Foundation
import XCTest
@testable import JibunKitCore

final class MiniAppLinkTests: XCTestCase {
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
