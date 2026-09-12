import XCTest
import JibunKitCore

final class MiniAppRegistryExpectationTests: XCTestCase {
    func testMissingDefinitionsAreReportedEvenWhenOtherFeaturesAreValid() {
        XCTAssertEqual(
            MiniAppValidator.validate(ids: [.counter, .reminder],
                                      expectedIDs: [.counter, MiniAppID("notes"), MiniAppID("records")]),
            [.missingExpectedID(rawValue: "notes"), .missingExpectedID(rawValue: "records")]
        )
    }

    func testExpectedSubsetAllowsOtherRegisteredFeatures() {
        XCTAssertTrue(MiniAppValidator.validate(ids: [.counter, .reminder, MiniAppID("notes")],
                                               expectedIDs: [MiniAppID("notes")]).isEmpty)
    }

    func testExpectedPresenceDoesNotHideDuplicateRegistration() {
        let issues = MiniAppValidator.validate(ids: [.counter, .counter], expectedIDs: [.counter])
        XCTAssertTrue(issues.contains(.duplicateID(rawValue: "counter")))
        XCTAssertFalse(issues.contains(.missingExpectedID(rawValue: "counter")))
    }
}
