import Foundation
import XCTest
@testable import JibunKitCore

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

    @MainActor
    func testOpensOnceTheAppBecomesActiveWithinTheTimeout() async throws {
        guard #available(macOS 13, *) else { throw XCTSkip("Needs Duration") }
        var checks = 0
        var opened: [URL] = []
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        try await MiniAppExternalURL.open(url, activationTimeout: .seconds(5), isActive: {
            checks += 1
            return checks > 2
        }, openURL: { opened.append($0); return true })
        XCTAssertEqual(opened, [url])
    }

    @MainActor
    func testRequestThatOutlivedItsTimeoutWhileSuspendedIsNotOpened() async throws {
        guard #available(macOS 13, *) else { throw XCTSkip("Needs Duration") }
        var opened = false
        // The first check stands in for the app being suspended past the
        // deadline; it is active when it runs again.
        var suspended = false
        do {
            try await MiniAppExternalURL.open(XCTUnwrap(URL(string: "https://example.com")),
                                              activationTimeout: .milliseconds(100), isActive: {
                if suspended { return true }
                suspended = true
                Thread.sleep(forTimeInterval: 0.3)
                return false
            }, openURL: { _ in opened = true; return true })
            XCTFail("An expired request must not open")
        } catch {
            XCTAssertEqual(error as? MiniAppExternalURLError, .inactive)
        }
        XCTAssertFalse(opened)
    }

    @MainActor
    func testReportsInactiveAndRejectedOpens() async throws {
        guard #available(macOS 13, *) else { throw XCTSkip("Needs Duration") }
        let url = try XCTUnwrap(URL(string: "sbux://"))
        do {
            try await MiniAppExternalURL.open(url, activationTimeout: .milliseconds(120), isActive: { false },
                                              openURL: { _ in true })
            XCTFail("Never active")
        } catch { XCTAssertEqual(error as? MiniAppExternalURLError, .inactive) }
        do {
            try await MiniAppExternalURL.open(url, activationTimeout: .seconds(1), isActive: { true },
                                              openURL: { _ in false })
            XCTFail("Rejected by the system")
        } catch { XCTAssertEqual(error as? MiniAppExternalURLError, .rejected) }
    }
}
