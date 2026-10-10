import Foundation
import XCTest
@testable import JibunKitCore

/// Core's views and errors read their text from the package's own string
/// tables, so the host shows them in the device language.
final class MiniAppCoreStringsTests: XCTestCase {
    func testCoreTablesShipEnglishAndJapanese() throws {
        for (language, retry, invalidInput) in [
            ("en", "Try Again", "Couldn’t confirm the received data’s format or destination (invalidInput)."),
            ("ja", "再試行", "受信データの形式または保存先を確認できませんでした（invalidInput）。"),
        ] {
            let path = try XCTUnwrap(Bundle.module.path(forResource: language, ofType: "lproj"), language)
            let bundle = try XCTUnwrap(Bundle(path: path))
            XCTAssertEqual(bundle.localizedString(forKey: "Try Again", value: nil, table: nil), retry)
            XCTAssertEqual(bundle.localizedString(
                forKey: "Couldn’t confirm the received data’s format or destination (invalidInput).",
                value: nil, table: nil), invalidInput)
        }
    }

    func testIncomingErrorsUseTheCoreTable() {
        XCTAssertEqual(MiniAppIncomingError.invalidInput.errorDescription,
                       String(localized: "Couldn’t confirm the received data’s format or destination (invalidInput).",
                              bundle: .module))
    }
}
