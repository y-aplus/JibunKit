import XCTest

/// Host wiring/management evidence only. Native Activity/Alarm registration and
/// OS button behavior are covered separately, including the physical device gate.
@MainActor
final class ContinuingHostUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "com.jibunkit.app")

    func testContinuingFeaturesUseNormalManagementWithoutRemovingOtherOwners() throws {
        continueAfterFailure = false
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        for owner in ["continuing-live-a", "continuing-live-b", "alarm-feature-a", "alarm-feature-b"] {
            XCUIDevice.shared.system.open(try XCTUnwrap(URL(string: "jibunkit://mini-app/" + owner)))
            let status = owner.hasPrefix("continuing-live") ? "live-\(owner.suffix(1)).status" : "\(owner).status"
            XCTAssertTrue(app.staticTexts[status].waitForExistence(timeout: 20), app.debugDescription)
            tap("miniapp.back-to-list")
        }
        tap("management.open")
        tap("management.disable.continuing-live-a")
        expect("management.status.continuing-live-a", "無効（データを保持）", timeout: 120)
        expect("management.status.continuing-live-b", "有効")
        expect("management.status.alarm-feature-a", "有効")
        app.terminate()
        app.launch()
        tap("management.open")
        expect("management.status.continuing-live-a", "無効（データを保持）")
        tap("management.enable.continuing-live-a")
        expect("management.status.continuing-live-a", "有効")
        tap("management.delete.alarm-feature-a")
        let confirm = app.alerts.buttons["削除"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        expect("management.status.alarm-feature-a", "削除済み", timeout: 120)
        expect("management.status.alarm-feature-b", "有効")
        expect("management.status.counter", "有効")
        expect("management.status.reminder", "有効")
        tap("management.enable.alarm-feature-a")
        expect("management.status.alarm-feature-a", "有効")
    }

    private func tap(_ id: String) {
        let button = app.buttons[id]
        for _ in 0..<5 where !button.isHittable { app.swipeUp() }
        for _ in 0..<7 where !button.isHittable { app.swipeDown() }
        XCTAssertTrue(button.waitForExistence(timeout: 15), app.debugDescription)
        button.tap()
    }

    private func expect(_ id: String, _ value: String, timeout: TimeInterval = 20) {
        for _ in 0..<5 where !app.staticTexts[id].exists { app.swipeUp() }
        for _ in 0..<7 where !app.staticTexts[id].exists { app.swipeDown() }
        let match = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", value),
            object: app.staticTexts[id])
        XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: timeout), .completed, app.debugDescription)
    }
}
