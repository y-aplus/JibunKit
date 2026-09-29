import Foundation
import XCTest
import JibunKitCore

final class MiniAppExternalURLTests: XCTestCase {
    func testOnlyAnotherAppsSchemeIsAccepted() throws {
        for accepted in ["https://example.com/a?b=c", "sbux://", "line://msg/text/hi", "mailto:a@example.com"] {
            XCTAssertNoThrow(try MiniAppExternalURL.validate(XCTUnwrap(URL(string: accepted))), accepted)
        }
        for rejected in ["jibunkit://mini-app/a", "JIBUNKIT://mini-app/a", "file:///tmp/a", "relative/path"] {
            XCTAssertThrowsError(try MiniAppExternalURL.validate(XCTUnwrap(URL(string: rejected))), rejected) {
                XCTAssertEqual($0 as? MiniAppExternalURLError, .invalidURL)
            }
        }
    }
}
